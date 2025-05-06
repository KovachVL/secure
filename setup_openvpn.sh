#!/bin/bash
set -e

# Цвета для вывода
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== Настройка OpenVPN сервера с аутентификацией по логину/паролю ===${NC}"

# Проверка запуска от имени root
if [ "$EUID" -ne 0 ]; then
  echo -e "${RED}Запустите скрипт от имени администратора (root)${NC}"
  exit 1
fi

# Проверка наличия Docker и Docker Compose
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker не установлен. Установите Docker перед запуском скрипта.${NC}"
    exit 1
fi

if ! command -v docker-compose &> /dev/null; then
    echo -e "${RED}Docker Compose не установлен. Установите Docker Compose перед запуском скрипта.${NC}"
    exit 1
fi

# Запрос IP-адреса сервера
read -p "Введите публичный IP-адрес вашего сервера: " SERVER_IP
if [ -z "$SERVER_IP" ]; then
    echo -e "${RED}IP-адрес не может быть пустым!${NC}"
    exit 1
fi

# Запрос имени пользователя и пароля
read -p "Создайте имя пользователя для VPN: " VPN_USER
if [ -z "$VPN_USER" ]; then
    echo -e "${RED}Имя пользователя не может быть пустым!${NC}"
    exit 1
fi

read -s -p "Создайте пароль для пользователя $VPN_USER: " VPN_PASSWORD
echo
if [ -z "$VPN_PASSWORD" ]; then
    echo -e "${RED}Пароль не может быть пустым!${NC}"
    exit 1
fi

# Создание необходимых директорий
echo -e "${GREEN}Создание директорий...${NC}"
mkdir -p config openvpn-data/keys
mkdir -p openvpn-data/auth

# Создание файла с учетными данными пользователя
echo "$VPN_USER" > openvpn-data/auth/credentials
echo "$VPN_PASSWORD" >> openvpn-data/auth/credentials
chmod 600 openvpn-data/auth/credentials

# Создание обновленной конфигурации сервера
echo -e "${GREEN}Создание конфигурации сервера...${NC}"
cat > config/server.conf << EOL
port 1194
proto udp
dev tun

ca keys/ca.crt
cert keys/server.crt
key keys/server.key
dh keys/dh.pem
tls-auth keys/ta.key 0

# Настройка аутентификации по логину/паролю
auth-user-pass-verify /etc/openvpn/auth/auth.sh via-file
script-security 3
client-cert-not-required
username-as-common-name

server 10.8.0.0 255.255.255.0
ifconfig-pool-persist /etc/openvpn/ipp.txt

push "redirect-gateway def1 bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"

keepalive 10 120
cipher AES-256-CBC
user nobody
group nogroup
persist-key
persist-tun
status /var/log/openvpn/openvpn-status.log
verb 3
EOL

# Создание скрипта аутентификации
echo -e "${GREEN}Создание скрипта аутентификации...${NC}"
cat > openvpn-data/auth/auth.sh << EOL
#!/bin/sh
###########################################################
# Check for a user/password file
###########################################################

if [ ! -r /etc/openvpn/auth/credentials ]; then
    echo "File with credentials not found!"
    exit 1
fi

###########################################################
# Get the username/password from the file passed as argument
###########################################################

username=\$(head -1 \$1)
password=\$(tail -1 \$1)

###########################################################
# Check username/password against what's in the file
###########################################################

stored_username=\$(head -1 /etc/openvpn/auth/credentials)
stored_password=\$(tail -1 /etc/openvpn/auth/credentials)

if [ "\$username" = "\$stored_username" ] && [ "\$password" = "\$stored_password" ]; then
    exit 0
else
    exit 1
fi
EOL

chmod +x openvpn-data/auth/auth.sh

# Создание Dockerfile
echo -e "${GREEN}Создание Dockerfile...${NC}"
cat > Dockerfile << EOL
FROM alpine:latest

# Установка OpenVPN и зависимостей
RUN apk add --update openvpn easy-rsa bash iptables && \\
    mkdir -p /etc/openvpn/keys && \\
    mkdir -p /var/log/openvpn && \\
    mkdir -p /etc/openvpn/auth && \\
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

# Копирование конфигурации сервера
COPY ./config/server.conf /etc/openvpn/

VOLUME ["/etc/openvpn"]

EXPOSE 1194/udp

CMD ["openvpn", "--config", "/etc/openvpn/server.conf"]
EOL

# Создание docker-compose.yml
echo -e "${GREEN}Создание docker-compose.yml...${NC}"
cat > docker-compose.yml << EOL
version: '3'

services:
  openvpn:
    build: .
    container_name: openvpn
    volumes:
      - ./openvpn-data:/etc/openvpn
    ports:
      - "1194:1194/udp"
    cap_add:
      - NET_ADMIN
    privileged: true
    restart: unless-stopped
EOL

# Генерация сертификатов
echo -e "${GREEN}Генерация сертификатов и ключей...${NC}"
echo -e "${YELLOW}Это может занять некоторое время...${NC}"

docker run --rm -v "$(pwd)/openvpn-data:/etc/openvpn" --name openvpn_setup alpine:latest /bin/sh -c "
    apk add --update openvpn easy-rsa bash &&
    cd /usr/share/easy-rsa &&
    ./easyrsa init-pki &&
    ./easyrsa --batch build-ca nopass &&
    ./easyrsa --batch build-server-full server nopass &&
    ./easyrsa gen-dh &&
    openvpn --genkey --secret /usr/share/easy-rsa/pki/ta.key &&
    mkdir -p /etc/openvpn/keys &&
    cp /usr/share/easy-rsa/pki/ca.crt /etc/openvpn/keys/ &&
    cp /usr/share/easy-rsa/pki/issued/server.crt /etc/openvpn/keys/ &&
    cp /usr/share/easy-rsa/pki/private/server.key /etc/openvpn/keys/ &&
    cp /usr/share/easy-rsa/pki/dh.pem /etc/openvpn/keys/ &&
    cp /usr/share/easy-rsa/pki/ta.key /etc/openvpn/keys/
"

# Создание конфигурации клиента
echo -e "${GREEN}Создание конфигурации клиента...${NC}"
mkdir -p clients

cat > clients/client.ovpn << EOL
client
dev tun
proto udp
remote $SERVER_IP 1194
resolv-retry infinite
nobind
persist-key
persist-tun
remote-cert-tls server
cipher AES-256-CBC
verb 3
auth-user-pass
auth-nocache

<ca>
$(cat openvpn-data/keys/ca.crt)
</ca>

<tls-auth>
$(cat openvpn-data/keys/ta.key)
</tls-auth>
key-direction 1
EOL

# Сборка и запуск контейнера
echo -e "${GREEN}Сборка и запуск OpenVPN сервера...${NC}"
docker-compose up -d

# Настройка маршрутизации
echo -e "${GREEN}Настройка маршрутизации...${NC}"
docker exec -it openvpn /bin/sh -c "
    iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o eth0 -j MASQUERADE &&
    echo 1 > /proc/sys/net/ipv4/ip_forward
"

echo -e "${GREEN}=== Настройка OpenVPN завершена! ===${NC}"
echo -e "${YELLOW}Ваш клиентский конфигурационный файл находится в: ${NC}clients/client.ovpn"
echo -e "${YELLOW}Для подключения используйте: ${NC}"
echo -e "${YELLOW}Логин: ${NC}$VPN_USER"
echo -e "${YELLOW}Пароль: ${NC}[Ваш пароль]"
echo -e "${GREEN}Не забудьте открыть порт 1194/UDP в вашем фаерволе!${NC}" 