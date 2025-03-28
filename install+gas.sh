#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.0.0_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"
MINER_BIN="popmd"
PACKAGES="jq curl wget unzip nano"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "❗ Скрипт должен быть запущен с правами root (sudo)."
    exit 1
fi

# Установка необходимых пакетов
install_packages() {
    echo "📦 Проверка и установка необходимых пакетов..."
    for pkg in $PACKAGES; do
        if dpkg -l | grep -q " $pkg "; then
            echo "✅ $pkg уже установлен."
        else
            echo "➤ Устанавливаем $pkg..."
            apt update && apt install -y "$pkg"
            if [ $? -ne 0 ]; then
                echo "❗ Ошибка установки $pkg."
                exit 1
            fi
        fi
    done
}

install_packages

# Установка майнера
if [ -d "$MINER_DIR" ]; then
    echo "✅ Майнер уже установлен."
else
    echo "⬇️ Загружаем майнер..."
    wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
    tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
    if [ ! -d "$MINER_DIR" ]; then
        echo "❗ Не удалось разархивировать майнер."
        exit 1
    fi
fi

# Настройка конфига
echo ""
echo "===== Настрой
