FROM alpine:latest

# Установка OpenVPN и зависимостей
RUN apk add --update openvpn easy-rsa bash && \
    mkdir -p /etc/openvpn/keys && \
    mkdir -p /var/log/openvpn && \
    mkdir -p /etc/openvpn/auth && \
    rm -rf /tmp/* /var/tmp/* /var/cache/apk/* /var/cache/distfiles/*

# Копирование конфигурации сервера
COPY ./config/server.conf /etc/openvpn/

VOLUME ["/etc/openvpn"]

EXPOSE 1194/udp

CMD ["openvpn", "--config", "/etc/openvpn/server.conf"] 