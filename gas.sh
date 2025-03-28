#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.0.0_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"

# Загружаем параметры из конфига
source "$CONFIG_FILE"

# --- Функция мониторинга газа ---
monitor_gas_and_stop_miner() {
    gas_limit=$1
    while true; do
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка: Не удалось получить данные о газе. Повтор через 30 секунд..."
            sleep 30
            continue
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Газ: $gas_price sat/vB (Порог: $gas_limit sat/vB)"

        if [ "$gas_price" -gt "$gas_limit" ]; then
            if pgrep -f "popmd" > /dev/null; then
                echo "Газ превышает порог ($gas_price > $gas_limit), останавливаем майнер..."
                pkill -f "popmd"
                echo "Майнер остановлен"
            fi
        fi
        sleep 30
    done
}

# Запуск мониторинга газа в фоновом режиме
if pgrep -f "popmd" > /dev/null; then
    echo "Майнер запущен, начинаем мониторинг газа..."
    monitor_gas_and_stop_miner "$POPM_STATIC_FEE" &
else
    echo "Майнер не запущен. Сначала запустите майнер."
fi
