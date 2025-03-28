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

# Установка пакетов
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
echo "===== Настройка майнера ====="
read -s -p "Введите ваш приватный ключ BTC: " btc_key
echo ""
read -p "Введите POPM_STATIC_FEE (например 4): " static_fee
if ! [[ "$static_fee" =~ ^[0-9]+$ ]]; then
    echo "❗ POPM_STATIC_FEE должен быть числом!"
    exit 1
fi

cat > "$CONFIG_FILE" <<EOF
#!/bin/bash
export POPM_BTC_PRIVKEY=${btc_key}
export POPM_STATIC_FEE=${static_fee}
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
EOF

chmod +x "$CONFIG_FILE"
echo "✅ Конфиг обновлен!"
echo "---------------------------"
cat "$CONFIG_FILE"
echo "---------------------------"

# Загружаем параметры
source "$CONFIG_FILE"

# Лог
log_message() {
    echo "\$(date '+%Y-%m-%d %H:%M:%S') - \$1"
}

# Очистка при выходе
cleanup() {
    echo "⛔ Прерывание скрипта..."
    pkill -f "$MINER_BIN"
    exit 0
}
trap cleanup INT

# Функция запуска майнера
start_miner() {
    log_message "🚀 Запускаем майнер..."
    cd "$MINER_DIR" || exit 1
    source "$CONFIG_FILE"
    ./"$MINER_BIN" &
}

# --- Основной цикл ---
while true; do
    gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
    if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
        log_message "❗ Не удалось получить данные о газе. Повтор через 30 сек."
        sleep 30
        continue
    fi
    log_message "Газ: \$gas_price sat/vB (Порог: \$POPM_STATIC_FEE sat/vB)"

    if [ "\$gas_price" -le "\$POPM_STATIC_FEE" ]; then
        if ! pgrep -f "\$MINER_BIN" > /dev/null; then
            start_miner
        else
            log_message "✅ Майнер уже запущен."
        fi
    else
        if pgrep -f "\$MINER_BIN" > /dev/null; then
            log_message "⚠️ Газ высокий (\$gas_price > \$POPM_STATIC_FEE). Останавливаем майнер..."
            pkill -f "\$MINER_BIN"
            log_message "🛑 Майнер остановлен."
        else
            log_message "❗ Газ высокий. Ожидаем..."
        fi
    fi

    sleep 30

    # Если майнер вылетел сам, перезапускаем
    if ! pgrep -f "\$MINER_BIN" > /dev/null && [ "\$gas_price" -le "\$POPM_STATIC_FEE" ]; then
        log_message "❗ Майнер выключился. Перезапуск..."
        start_miner
    fi
done
