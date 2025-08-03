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

# --- Функция получения текущего блока Bitcoin ---
get_current_block() {
    current_block=$(curl -s https://blockstream.info/api/blocks/tip/height 2>/dev/null)
    if [ -z "$current_block" ] || ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
        echo "0"
    else
        echo "$current_block"
    fi
}

# --- Функция проверки статуса транзакции ---
check_transaction_status() {
    local tx_hash=$1
    local status=$(curl -s "https://blockstream.info/api/tx/$tx_hash" 2>/dev/null | jq -r '.status.block_height' 2>/dev/null)
    
    if [ "$status" = "null" ] || [ -z "$status" ]; then
        echo "unconfirmed"
    else
        echo "confirmed"
    fi
}

# --- Функция ожидания нового блока ---
wait_for_new_block() {
    local start_block=$(get_current_block)
    local current_block=$start_block
    local timeout_seconds=1200  # 20 минут максимум
    
    log_message "Ожидаем новый блок. Текущий блок: $start_block"
    
    local elapsed=0
    while [ "$current_block" -eq "$start_block" ] && [ $elapsed -lt $timeout_seconds ]; do
        sleep 30  # Проверяем каждые 30 секунд
        current_block=$(get_current_block)
        elapsed=$((elapsed + 30))
        
        if [ $((elapsed % 300)) -eq 0 ]; then  # Каждые 5 минут
            log_message "Ожидание нового блока... Прошло: $((elapsed / 60)) минут"
        fi
    done
    
    if [ "$current_block" -gt "$start_block" ]; then
        log_message "Новый блок найден: $current_block (прошло $((elapsed / 60)) минут)"
        return 0
    else
        log_message "Таймаут ожидания нового блока (20 минут)"
        return 1
    fi
}

# --- Функция ожидания конкретного блока ---
wait_for_specific_block() {
    local target_block=$1
    local current_block=$(get_current_block)
    local timeout_seconds=1200  # 20 минут максимум
    
    log_message "Ожидаем конкретный блок: $target_block (текущий: $current_block)"
    
    local elapsed=0
    while [ "$current_block" -lt "$target_block" ] && [ $elapsed -lt $timeout_seconds ]; do
        sleep 30  # Проверяем каждые 30 секунд
        current_block=$(get_current_block)
        elapsed=$((elapsed + 30))
        
        if [ $((elapsed % 300)) -eq 0 ]; then  # Каждые 5 минут
            log_message "Ожидание блока $target_block... Текущий: $current_block, прошло: $((elapsed / 60)) минут"
        fi
    done
    
    if [ "$current_block" -ge "$target_block" ]; then
        log_message "Блок $target_block найден! (прошло $((elapsed / 60)) минут)"
        return 0
    else
        log_message "Таймаут ожидания блока $target_block (20 минут)"
        return 1
    fi
}

# --- Функция ожидания завершения блока ---
wait_for_block_completion() {
    local target_block=$1
    local current_block=$(get_current_block)
    local timeout_seconds=600  # 10 минут максимум
    
    log_message "Ожидаем завершение блока: $target_block (текущий: $current_block)"
    
    local elapsed=0
    # Ждем пока текущий блок станет больше целевого (блок завершен)
    while [ "$current_block" -le "$target_block" ] && [ $elapsed -lt $timeout_seconds ]; do
        sleep 30  # Проверяем каждые 30 секунд
        current_block=$(get_current_block)
        elapsed=$((elapsed + 30))
        
        if [ $((elapsed % 120)) -eq 0 ]; then  # Каждые 2 минуты
            log_message "Ожидание завершения блока $target_block... Текущий: $current_block, прошло: $((elapsed / 60)) минут"
        fi
    done
    
    if [ "$current_block" -gt "$target_block" ]; then
        log_message "Блок $target_block завершен! Текущий блок: $current_block (прошло $((elapsed / 60)) минут)"
        return 0
    else
        log_message "Таймаут ожидания завершения блока $target_block (10 минут)"
        return 1
    fi
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

        # Проверяем газ с учетом быстрого подтверждения
        if [ "$gas_price" -gt "$gas_limit" ]; then
            if pgrep -f "popmd" > /dev/null; then
                log_message "Газ превышает порог ($gas_price > $gas_limit), останавливаем майнер..."
                pkill -f "popmd"
                log_message "Майнер остановлен"
            fi
        fi
        
        # Получаем порог газа из конфига (теперь равен комиссии)
        gas_threshold=$POPM_STATIC_FEE
        
        # Проверяем оптимальные условия для майнинга
        if [ "$gas_price" -le "$gas_threshold" ] && pgrep -f "popmd" > /dev/null; then
            log_message "Газ оптимальный ($gas_price <= $gas_threshold), майнер может работать с комиссией $POPM_STATIC_FEE sat/vB"
        elif [ "$gas_price" -gt "$gas_threshold" ] && pgrep -f "popmd" > /dev/null; then
            log_message "Газ слишком высокий ($gas_price > $gas_threshold), останавливаем майнер для экономии..."
            pkill -f "popmd"
            log_message "Майнер остановлен из-за высокого газа"
        fi
        
        # Проверяем транзакции если майнер запущен
        if pgrep -f "popmd" > /dev/null; then
            # Проверяем, есть ли файл логов
            if [ ! -f "$LOG_FILE" ]; then
                log_message "⚠️  Файл логов не найден: $LOG_FILE"
            elif [ ! -s "$LOG_FILE" ]; then
                log_message "⚠️  Файл логов пуст: $LOG_FILE"
            fi
            
            # Проверяем логи на наличие успешной транзакции
            if [ -f "$LOG_FILE" ] && grep -q "Successfully broadcast PoP transaction" "$LOG_FILE" 2>/dev/null; then
                # Получаем текущий блок Bitcoin
                current_block=$(get_current_block)
                
                # Подсчитываем количество транзакций
                tx_count=$(grep -c "Successfully broadcast PoP transaction" "$LOG_FILE" 2>/dev/null || echo "0")
                
                # Получаем время первой и последней транзакции
                first_tx_time=$(grep "Successfully broadcast PoP transaction" "$LOG_FILE" | head -1 | awk '{print $1, $2}' 2>/dev/null)
                last_tx_time=$(grep "Successfully broadcast PoP transaction" "$LOG_FILE" | tail -1 | awk '{print $1, $2}' 2>/dev/null)
                
                # Вычисляем разницу во времени
                if [ -n "$first_tx_time" ] && [ -n "$last_tx_time" ] && [ "$tx_count" -gt 1 ]; then
                    # Конвертируем время в секунды для вычисления разницы
                    first_epoch=$(date -d "$first_tx_time" +%s 2>/dev/null)
                    last_epoch=$(date -d "$last_tx_time" +%s 2>/dev/null)
                    
                    if [ -n "$first_epoch" ] && [ -n "$last_epoch" ]; then
                        time_diff=$((last_epoch - first_epoch))
                        time_diff_minutes=$((time_diff / 60))
                        time_diff_seconds=$((time_diff % 60))
                        
                        log_message "БЛОК $current_block: Майнер отправил $tx_count транзакций за ${time_diff_minutes}м ${time_diff_seconds}с"
                    else
                        log_message "БЛОК $current_block: Майнер отправил $tx_count транзакций (время не удалось вычислить)"
                    fi
                else
                    log_message "БЛОК $current_block: Майнер отправил $tx_count транзакций"
                fi
                
                log_message "Обнаружена успешная транзакция! Останавливаем майнер..."
                pkill -f "popmd"
                log_message "Майнер остановлен после первой транзакции"
                
                # Ждем завершения текущего блока (чтобы транзакция попала в правильный блок)
                log_message "Ожидаем завершение текущего блока $current_block..."
                if wait_for_block_completion "$current_block"; then
                    log_message "Блок $current_block завершен, транзакция должна попасть в правильный блок"
                else
                    log_message "Таймаут ожидания завершения блока $current_block"
                fi
                
                # Короткая пауза перед следующим циклом
                log_message "Короткая пауза перед следующим циклом..."
                sleep 30
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
    
    # Проверяем логи перед удалением
    if [ -f "/tmp/popmd_$$.log" ]; then
        log_message "=== АНАЛИЗ ЛОГОВ МАЙНЕРА ==="
        if [ -s "/tmp/popmd_$$.log" ]; then
            log_message "Последние строки логов майнера:"
            tail -10 "/tmp/popmd_$$.log" | while read line; do
                log_message "МАЙНЕР: $line"
            done
        else
            log_message "Файл логов пуст - майнер не успел запуститься или завершился с ошибкой"
        fi
        
        # Проверяем наличие транзакций
        if grep -q "Successfully broadcast PoP transaction" "/tmp/popmd_$$.log" 2>/dev/null; then
            tx_count=$(grep -c "Successfully broadcast PoP transaction" "/tmp/popmd_$$.log")
            log_message "✅ Найдено транзакций: $tx_count"
        else
            log_message "❌ Транзакции не найдены в логах"
        fi
        
        # Проверяем ошибки
        if grep -q "ERROR\|error\|Error" "/tmp/popmd_$$.log" 2>/dev/null; then
            log_message "⚠️  Найдены ошибки в логах:"
            grep -i "error" "/tmp/popmd_$$.log" | tail -3 | while read line; do
                log_message "ОШИБКА: $line"
            done
        fi
        
        log_message "=== КОНЕЦ АНАЛИЗА ==="
    else
        log_message "❌ Файл логов не найден"
    fi
    
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
