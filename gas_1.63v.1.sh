#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.6.3_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"

# Загружаем параметры из конфига
source "$CONFIG_FILE"

# Функция логирования
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
}

# --- Функция мониторинга газа и транзакций ---
monitor_gas_and_transactions() {
    gas_limit=$1
    
    # Создаем временный файл для логов майнера
    LOG_FILE="/tmp/popmd_$$.log"
    
    while true; do
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            log_message "Ошибка: Не удалось получить данные о газе. Повтор через 30 секунд..."
            sleep 30
            continue
        fi
        log_message "Газ: $gas_price sat/vB (Порог: $gas_limit sat/vB)"

        # Проверяем газ
        if [ "$gas_price" -gt "$gas_limit" ]; then
            if pgrep -f "popmd" > /dev/null; then
                log_message "Газ превышает порог ($gas_price > $gas_limit), останавливаем майнер..."
                pkill -f "popmd"
                log_message "Майнер остановлен"
            fi
        fi
        
        # Проверяем транзакции если майнер запущен
        if pgrep -f "popmd" > /dev/null; then
            # Проверяем логи на наличие успешной транзакции
            if [ -f "$LOG_FILE" ] && grep -q "Successfully broadcast PoP transaction" "$LOG_FILE" 2>/dev/null; then
                log_message "Обнаружена успешная транзакция! Останавливаем майнер..."
                pkill -f "popmd"
                log_message "Майнер остановлен после первой транзакции"
                
                # Ждем 11 минут до следующего блока
                log_message "Ожидание 11 минут до следующего блока..."
                sleep 660
                log_message "Таймаут завершен, готов к следующему циклу"
            fi
        fi
        
        sleep 5  # Проверяем каждые 5 секунд
    done
}

# Ожидание запуска майнера
log_message "Ожидаем запуск майнера..."
while ! pgrep -f "popmd" > /dev/null; do
    sleep 5
done

log_message "Майнер запущен, начинаем мониторинг газа и транзакций..."

# Запускаем мониторинг в фоне
monitor_gas_and_transactions "$POPM_STATIC_FEE" &
monitor_pid=$!

# Основной цикл - ждем завершения майнера и готовимся к следующему запуску
while true; do
    # Ждем завершения майнера
    while pgrep -f "popmd" > /dev/null; do
        sleep 5
    done
    
    log_message "Майнер завершил работу."
    
    # Останавливаем текущий мониторинг
    kill $monitor_pid 2>/dev/null
    
    # Удаляем временный файл логов
    rm -f "/tmp/popmd_$$.log"
    
    # Ждем следующего запуска майнера
    log_message "Ожидаем следующий запуск майнера..."
    while ! pgrep -f "popmd" > /dev/null; do
        sleep 5
    done
    
    log_message "Майнер запущен снова, возобновляем мониторинг..."
    
    # Запускаем мониторинг снова
    monitor_gas_and_transactions "$POPM_STATIC_FEE" &
    monitor_pid=$!
done 
