#!/bin/bash
set -Eeuo pipefail

# =============== Параметры ===============
VERSION="v1.6.3"
ARCHIVE="heminetwork_${VERSION}_linux_amd64.tar.gz"
MINER_DIR="$HOME/heminetwork_${VERSION}_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"
PID_FILE="$MINER_DIR/popmd.pid"
LAST_BLOCK_FILE="$MINER_DIR/.last_attempt_block"
COOLDOWN_FLAG="$MINER_DIR/.cooldown"
LOG_FILE="$MINER_DIR/miner_output.log"

# Время кулдауна в секундах (по умолчанию 600 = 10 минут)
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-600}"

# Требуемые утилиты
PACKAGES="jq curl wget unzip nano"

# =============== Проверка прав ===============
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт должен быть запущен с правами root (используйте sudo)."
    exit 1
fi

# =============== Вспомогательные функции ===============
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*"; }

install_packages() {
    log "Проверка необходимых пакетов..."
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -y
    for pkg in $PACKAGES; do
        if ! command -v "$pkg" >/dev/null 2>&1; then
            log "$pkg не найден, устанавливаем..."
            apt-get install -y "$pkg"
        fi
    done
}

download_and_unpack() {
    if [ -d "$MINER_DIR" ]; then
        log "Майнер уже установлен, пропускаем установку."
        return
    fi
    log "Майнер не найден, начинаем установку..."
    apt-get update -y && apt-get upgrade -y
    curl --fail -L -o "$ARCHIVE" "https://github.com/hemilabs/heminetwork/releases/download/${VERSION}/${ARCHIVE}"
    tar -xvzf "$ARCHIVE"
    rm -f "$ARCHIVE"
}

write_config() {
    echo ""
    echo "===== Настройка майнера ====="
    read -s -p "Введите ваш приватный ключ BTC: " btc_key; echo
    read -p "Введите POPM_STATIC_FEE (например 1): " static_fee
    if ! [[ "$static_fee" =~ ^[0-9]+$ ]]; then
        echo "Ошибка: POPM_STATIC_FEE должен быть числом!"; exit 1
    fi
    umask 077
    cat > "$CONFIG_FILE" <<EOF
#!/bin/bash
export POPM_BTC_PRIVKEY='${btc_key}'
export POPM_STATIC_FEE=${static_fee}
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
EOF
    chmod 600 "$CONFIG_FILE"
    log "✅ Конфиг обновлен"
}

safe_curl() {
    curl --fail --silent --show-error --connect-timeout 5 --max-time 15 "$@"
}

get_tip_block() {
    safe_curl https://mempool.space/api/v1/blocks/tip/height || echo ""
}

get_fastest_fee() {
    safe_curl https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null || echo ""
}

wait_for_new_block() {
    local last_block=""
    last_block=$(get_tip_block)
    while ! [[ "$last_block" =~ ^[0-9]+$ ]]; do
        log "Не удалось получить номер блока. Повтор через 30 сек..."
        sleep 30
        last_block=$(get_tip_block)
    done
    log "Ожидание нового блока..."
    while true; do
        current_block=$(get_tip_block)
        if [[ "$current_block" =~ ^[0-9]+$ ]] && [ "$current_block" -gt "$last_block" ]; then
            log "Новый блок $current_block"
            break
        fi
        sleep 10
    done
}

stop_miner_if_running() {
    if [ -f "$PID_FILE" ]; then
        local pid
        pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
        if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
            kill "$pid" || true
            log "Остановили майнер (PID $pid)"
        else
            pkill -x popmd || true
        fi
        rm -f "$PID_FILE"
    else
        pkill -x popmd || true
    fi
}

start_once_per_block_with_cooldown() {
    source "$CONFIG_FILE"
    cd "$MINER_DIR"
    chmod +x ./popmd || true

    while true; do
        # уважаем кулдаун
        if [ -f "$COOLDOWN_FLAG" ]; then
            log "Обнаружен кулдаун. Ждём ${COOLDOWN_SECONDS} сек перед перезапуском..."
            rm -f "$COOLDOWN_FLAG"
            sleep "$COOLDOWN_SECONDS"
        fi

        # газ
        gas_price=$(get_fastest_fee)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            log "Не удалось получить газ. Повтор через 30 сек..."
            sleep 30
            continue
        fi
        log "Газ: $gas_price sat/vB (Порог: $POPM_STATIC_FEE sat/vB)"

        # номер блока
        current_block=$(get_tip_block)
        if ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
            log "Не удалось получить текущий блок. Повтор через 30 сек..."
            sleep 30
            continue
        fi
        last_attempt_block=-1
        if [ -f "$LAST_BLOCK_FILE" ]; then
            last_attempt_block=$(cat "$LAST_BLOCK_FILE" 2>/dev/null || echo "-1")
        fi
        if [ "$current_block" = "$last_attempt_block" ]; then
            log "Попытка на блок $current_block уже была. Ожидаем следующий блок..."
            sleep 10
            continue
        fi

        if [ "$gas_price" -le "$POPM_STATIC_FEE" ]; then
            log "Газ в норме, запускаем майнер..."
            echo "$current_block" > "$LAST_BLOCK_FILE"
            ./popmd > "$LOG_FILE" 2>&1 &
            miner_pid=$!
            echo $miner_pid > "$PID_FILE"
            wait $miner_pid || true

            # По завершении всегда вводим кулдаун
            log "Завершили попытку на блок $current_block. Кулдаун ${COOLDOWN_SECONDS} сек..."
            touch "$COOLDOWN_FLAG"
            sleep "$COOLDOWN_SECONDS"
        else
            log "Газ слишком высокий, продолжаем ожидание..."
            sleep 30
        fi
    done
}

monitor_gas_and_stop() {
    source "$CONFIG_FILE"
    while true; do
        gas_price=$(get_fastest_fee)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            log "[монитор] Не удалось получить газ. Повтор через 30 сек..."
            sleep 30
            continue
        fi
        log "[монитор] Газ: $gas_price sat/vB (Порог: $POPM_STATIC_FEE sat/vB)"
        if [ "$gas_price" -gt "$POPM_STATIC_FEE" ]; then
            if [ -f "$PID_FILE" ]; then
                pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
                if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
                    log "[монитор] Газ > порога, останавливаем майнер (PID $pid)..."
                    kill "$pid" || true
                    touch "$COOLDOWN_FLAG"
                    log "[монитор] Установлен кулдаун ${COOLDOWN_SECONDS} сек"
                else
                    if pgrep -x popmd >/dev/null 2>&1; then
                        log "[монитор] Останавливаем popmd по имени процесса..."
                        pkill -x popmd || true
                        touch "$COOLDOWN_FLAG"
                    fi
                fi
            else
                if pgrep -x popmd >/dev/null 2>&1; then
                    log "[монитор] Останавливаем popmd по имени процесса..."
                    pkill -x popmd || true
                    touch "$COOLDOWN_FLAG"
                fi
            fi
        fi
        sleep 30
    done
}

cleanup() {
    log "Прерывание скрипта..."
    stop_miner_if_running
    exit 0
}
trap cleanup INT TERM

# =============== Выполнение ===============
install_packages
download_and_unpack

if [ ! -f "$CONFIG_FILE" ]; then
    write_config
else
    log "Конфиг найден, пропускаем настройку."
fi

# Запуск двух задач в одном скрипте: монитор и основной цикл
log "Старт мониторинга газа..."
monitor_gas_and_stop &

log "Старт основного цикла майнера..."
start_once_per_block_with_cooldown


