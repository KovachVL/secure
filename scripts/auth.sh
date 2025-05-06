#!/bin/bash

# Проверка, что скрипт получил правильное количество аргументов
if [ $# -ne 3 ]
then
  echo "Usage: $0 <username> <password> <auth_file>"
  exit 1
fi

USERNAME=$1
PASSWORD=$2
AUTH_FILE=$3

# Проверка существования файла аутентификации
if [ ! -f "$AUTH_FILE" ]
then
  echo "ERROR: Authentication file $AUTH_FILE does not exist!"
  exit 1
fi

# Проверка логина и пароля
grep -q "^${USERNAME},${PASSWORD}$" "$AUTH_FILE"

if [ $? -eq 0 ]
then
  echo "Authentication successful for user: $USERNAME"
  exit 0
else
  echo "Authentication failed for user: $USERNAME"
  exit 1
fi 