#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.0.0_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"

# Загружаем параметры из конфига
source "$CONFIG_FILE"

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# Запрос значения для газа
read -p "Введите газ, который следует ожидать для запуска майнера (например 1): " gas_limit

# Проверка, что значение газа является числом
if ! [[ "$gas_limit" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Ошибка: Газ для ожидания должен быть числом!"
    exit 1
fi

# --- Функция мониторинга газа --- 
monitor_gas_and_stop_miner() {
    while true; do
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            log_message "Ошибка: Не удалось получить данные о газе. Повтор через 30 секунд..."
            sleep 30
            continue
        fi
        log_message "Газ: $gas_price sat/vB (Порог: $gas_limit sat/vB)"

        if [ "$gas_price" -gt "$gas_limit" ]; then
            if pgrep -f "popmd" > /dev/null; then
                log_message "Газ превышает порог ($gas_price > $gas_limit), останавливаем майнер..."
                pkill -f "popmd"
                log_message "Майнер остановлен"
            fi
        fi
        sleep 30
    done
}

# Ожидание запуска майнера
while ! pgrep -f "popmd" > /dev/null; do
    log_message "Майнер не запущен. Ожидаем запуск..."
    sleep 30
done

log_message "Майнер запущен, начинаем мониторинг газа..."
monitor_gas_and_stop_miner "$gas_limit" &

# Дополнительная проверка на случай если майнер завершил работу
while pgrep -f "popmd" > /dev/null; do
    sleep 5
done

log_message "Майнер завершил работу."

