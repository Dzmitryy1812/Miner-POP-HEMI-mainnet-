# Проверка наличия jq
if ! command -v jq &> /dev/null; then
    log_message "Ошибка: jq не установлен. Установите: sudo apt install jq"
    exit 1
fi

# Параметры
MINER_DIR="$HOME/heminetwork_v1.6.3_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"

# Загружаем параметры из конфига
source "$CONFIG_FILE"

# Функция логирования
# Параметры логирования
LOG_FILE="$MINER_DIR/miner.log"
MAX_LOG_SIZE=$((10*1024*1024)) # 10MB

log_message() {
    # Запись в консоль
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1"
    
    # Запись в файл с ротацией
    if [ -f "$LOG_FILE" ] && [ $(wc -c <"$LOG_FILE") -ge $MAX_LOG_SIZE ]; then
        mv "$LOG_FILE" "${LOG_FILE}.1"
    fi
    
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" >> "$LOG_FILE"
}

# --- Функция мониторинга газа ---
monitor_gas_and_stop_miner() {
    gas_limit=$1
    # Параметры RPC нода Hemi (можно менять при необходимости)
    local RPC_ENDPOINT="wss://pop.hemi.network/v1/ws/public"
    local CHECK_INTERVAL=30
    
    # Параметры RPC нода Hemi (можно менять при необходимости)
    local RPC_ENDPOINT="wss://pop.hemi.network/v1/ws/public"
    local CHECK_INTERVAL=30
    
    # Безопасная инициализация высоты блока
    local last_block_height=0
    local initial_height=$(curl -s "${RPC_ENDPOINT}/status" 2>/dev/null | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
    if [[ "$initial_height" =~ ^[0-9]+$ ]]; then
        last_block_height=$initial_height
        log_message "Начальная высота блока: $last_block_height"
    else
        log_message "Предупреждение: Не удалось получить начальную высоту блока, начинаем с 0"
    fi
    
    while true; do
        # Получаем высоту блока и газ
        current_block_height=$(curl -s "${RPC_ENDPOINT}/status" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)

        # Проверка ошибок RPC
        if ! [[ "$current_block_height" =~ ^[0-9]+$ ]]; then
            log_message "Ошибка RPC: Нет связи с нодой. Повтор через 30 секунд..."
            sleep 30
            sleep $CHECK_INTERVAL
            continue
        fi

        # Проверка нового блока
        if [ "$current_block_height" -gt "$last_block_height" ]; then
            last_block_height=$current_block_height
            
            if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
                log_message "Ошибка: Не удалось получить газ через mempool.space"
                continue
            fi
            
            log_message "Блок #${current_block_height} | Газ: $gas_price sat/vB | Порог: $gas_limit sat/vB"

            if [ "$gas_price" -gt "$gas_limit" ]; then
                if pgrep -f "popmd" > /dev/null; then
                    log_message "СТОП: Газ $gas_price > $gas_limit, останавливаю майнер..."
                    pkill -f "popmd"
                    log_message "Майнер остановлен"
                fi
            fi
        fi
        
        sleep $CHECK_INTERVAL
    done
}

# Ожидание запуска майнера
while ! pgrep -f "popmd" > /dev/null; do
    log_message "Майнер не запущен. Ожидаем запуск..."
    sleep 30
done

log_message "Майнер запущен, начинаем мониторинг газа..."
monitor_gas_and_stop_miner "$POPM_STATIC_FEE" &

# Дополнительная проверка на случай если майнер завершил работу
# Параметры перезапуска
MAX_RETRIES=3
RETRY_TIMEOUT=600  # 10 минут
retry_count=0

while pgrep -f "popmd" > /dev/null; do
    sleep 5
done

log_message "Майнер завершил работу. Анализ логов..."
# Проверка на успешные транзакции
success_tx=$(grep -c "успешная транзакция" "$MINER_DIR/miner.log")

# Ожидание нового блока
while true; do
    current_block_height=$(curl -s "${RPC_ENDPOINT}/status" | jq -r '.result.sync_info.latest_block_height' 2>/dev/null)
    if [[ "$current_block_height" =~ ^[0-9]+$ ]]; then
        log_message "Ожидание нового блока..."
        sleep 30  # Ожидание перед следующей проверкой
        break
    else
        log_message "Ошибка RPC: Нет связи с нодой. Повтор через 30 секунд..."
        sleep 30
    fi
done

if [ "$success_tx" -eq 0 ] && [ "$retry_count" -lt "$MAX_RETRIES" ]; then
    retry_count=$((retry_count+1))
    log_message "Нет успешных транзакций. Попытка $retry_count/$MAX_RETRIES через $RETRY_TIMEOUT сек"
    sleep $RETRY_TIMEOUT
    log_message "Перезапуск майнера..."
    # Добавьте команду запуска майнера из install_1.63v1.sh
else
    log_message "Успешных транзакций: $success_tx. Работа завершена"
fi
