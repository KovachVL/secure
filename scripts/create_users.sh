#!/bin/bash

AUTH_FILE="/etc/openvpn/auth/users.csv"

# Создание директории для аутентификации, если не существует
mkdir -p /etc/openvpn/auth

# Проверка существования файла аутентификации
if [ ! -f "$AUTH_FILE" ]; then
    echo "Создание файла аутентификации..."
    touch "$AUTH_FILE"
    chmod 600 "$AUTH_FILE"  # Только root может читать/писать
fi

# Функция для добавления/обновления пользователя
add_user() {
    local username="$1"
    local password="$2"
    
    # Удаление пользователя, если существует
    sed -i "/^${username},/d" "$AUTH_FILE"
    
    # Добавление пользователя
    echo "${username},${password}" >> "$AUTH_FILE"
    echo "Пользователь $username добавлен/обновлен."
}

# Функция для удаления пользователя
delete_user() {
    local username="$1"
    
    # Проверка, существует ли пользователь
    if grep -q "^${username}," "$AUTH_FILE"; then
        sed -i "/^${username},/d" "$AUTH_FILE"
        echo "Пользователь $username удален."
    else
        echo "Пользователь $username не найден."
    fi
}

# Функция для вывода списка пользователей
list_users() {
    echo "Список пользователей:"
    cat "$AUTH_FILE" | cut -d ',' -f 1
}

# Создание дефолтного пользователя, если не указаны аргументы
if [ $# -eq 0 ]; then
    echo "Создание дефолтного пользователя 'vpnuser'..."
    add_user "vpnuser" "vpnpassword"
    echo "Дефолтный пользователь создан:"
    echo "Логин: vpnuser"
    echo "Пароль: vpnpassword"
    echo ""
    echo "ВНИМАНИЕ: Смените дефолтные учетные данные в производственной среде!"
    exit 0
fi

# Парсинг аргументов
case "$1" in
    add)
        if [ $# -ne 3 ]; then
            echo "Использование: $0 add <username> <password>"
            exit 1
        fi
        add_user "$2" "$3"
        ;;
    delete)
        if [ $# -ne 2 ]; then
            echo "Использование: $0 delete <username>"
            exit 1
        fi
        delete_user "$2"
        ;;
    list)
        list_users
        ;;
    *)
        echo "Использование: $0 [add <username> <password> | delete <username> | list]"
        echo "Без аргументов будет создан дефолтный пользователь."
        exit 1
        ;;
esac

exit 0 