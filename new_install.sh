#!/bin/bash
set -Eeuo pipefail

# =============== Параметры ===============
VERSION="v1.6.3"
ARCHIVE="heminetwork_${VERSION}_linux_amd64.tar.gz"
MINER_DIR="$HOME/heminetwork_${VERSION}_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"
PID_FILE="$MINER_DIR/popmd.pid"
LAST_BLOCK_FILE="$MINER_DIR/.last_attempt_block"
COOLDOWN_FLAG="$MINER_DIR/.cooldown" # устаревший флаг (сохраняем совместимость)
WAIT_NEXT_FLAG="$MINER_DIR/.wait_next_block"
LOG_FILE="$MINER_DIR/miner_output.log"

# Время кулдауна (больше не используется, оставлено для совместимости)
COOLDOWN_SECONDS="${COOLDOWN_SECONDS:-600}"

# Динамический порог, гистерезис и сглаживание
DYN_ENABLED="${DYN_ENABLED:-1}"
DYN_P="${DYN_P:-25}"
DYN_N="${DYN_N:-50}"
HYST_DELTA="${HYST_DELTA:-1}"
HYST_RATIO="${HYST_RATIO:-0}"
SMOOTH_M="${SMOOTH_M:-5}"
START_STREAK_K="${START_STREAK_K:-3}"
BLOCK_WINDOW_SEC="${BLOCK_WINDOW_SEC:-0}"
FEE_HISTORY_FILE="$MINER_DIR/.fee_history"

# Telegram уведомления (опционально)
TELEGRAM_BOT_TOKEN="${TELEGRAM_BOT_TOKEN:-}"
TELEGRAM_CHAT_ID="${TELEGRAM_CHAT_ID:-}"

# Мониторинг баланса (опционально)
BALANCE_MIN_USD="${BALANCE_MIN_USD:-10}"

# Длинное устойчиво низкое окно (минуты) для старта вне блока
LONG_LOW_MINUTES="${LONG_LOW_MINUTES:-0}" # 0 = выключено

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
    read -p "Необязательно: BTC-адрес для мониторинга баланса (пусто чтобы пропустить): " btc_addr
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
export POPM_BTC_ADDRESS='${btc_addr}'
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

send_tg() {
    # использует TELEGRAM_BOT_TOKEN и TELEGRAM_CHAT_ID
    if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then return; fi
    local text="$1"
    local url="https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage"
    safe_curl -X POST -H 'Content-Type: application/json' \
        -d "{\"chat_id\":\"${TELEGRAM_CHAT_ID}\",\"text\":\"${text//\"/\\\"}\"}" "$url" >/dev/null 2>&1 || true
}

# Цены и баланс
get_btc_price_usd() {
    # mempool.space prices
    safe_curl https://mempool.space/api/v1/prices | jq -r '.USD' 2>/dev/null || echo ""
}

get_address_balance_sats() {
    local addr="$1"
    [ -z "$addr" ] && echo "" && return
    local js
    js=$(safe_curl "https://mempool.space/api/address/${addr}" || echo "")
    if [ -z "$js" ]; then echo ""; return; fi
    # chain + mempool (эффективный баланс)
    echo "$js" | jq -r '(.chain_stats.funded_txo_sum - .chain_stats.spent_txo_sum) + (.mempool_stats.funded_txo_sum - .mempool_stats.spent_txo_sum)' 2>/dev/null
}

get_balance_usd() {
    local addr="$1"
    local sats price usd
    sats=$(get_address_balance_sats "$addr")
    price=$(get_btc_price_usd)
    if ! [[ "$sats" =~ ^[0-9]+$ ]] || ! [[ "$price" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then echo ""; return; fi
    # usd = sats * 1e-8 * price
    usd=$(awk -v s="$sats" -v p="$price" 'BEGIN{printf("%.2f", s/100000000.0*p)}')
    echo "$usd"
}

balance_guard_or_wait() {
    # если адрес задан и баланс в USD < порога, останавливаем майнер (если запущен) и ждём нового блока
    local addr="$POPM_BTC_ADDRESS"
    if [ -z "$addr" ]; then return 0; fi
    local usd
    usd=$(get_balance_usd "$addr")
    if [ -z "$usd" ]; then return 0; fi
    log "[баланс] ${usd} USD (порог ${BALANCE_MIN_USD} USD)"
    # сравнение с порогом
    below=$(awk -v u="$usd" -v m="$BALANCE_MIN_USD" 'BEGIN{print (u<m)?1:0}')
    if [ "$below" -eq 1 ]; then
        log "Баланс ниже порога, останавливаем майнер и ждём следующий блок"
        stop_miner_if_running
        tip=$(get_tip_block)
        if [[ "$tip" =~ ^[0-9]+$ ]]; then echo "$tip" > "$LAST_BLOCK_FILE"; fi
        touch "$WAIT_NEXT_FLAG"
        send_tg "[HEMI] Низкий баланс: ${usd} USD < ${BALANCE_MIN_USD} USD. Майнер остановлен до следующего блока."
        return 1
    fi
    return 0
}

add_fee_sample() {
    local fee="$1"
    [ -z "$fee" ] && return
    echo "$fee" >> "$FEE_HISTORY_FILE"
    # обрезаем до DYN_N последних строк
    local lines
    lines=$(wc -l < "$FEE_HISTORY_FILE" 2>/dev/null || echo 0)
    if [ "$lines" -gt "$DYN_N" ]; then
        tail -n "$DYN_N" "$FEE_HISTORY_FILE" > "${FEE_HISTORY_FILE}.tmp" && mv "${FEE_HISTORY_FILE}.tmp" "$FEE_HISTORY_FILE"
    fi
}

percentile_fee() {
    local p="$1"
    [ ! -s "$FEE_HISTORY_FILE" ] && echo "" && return
    mapfile -t arr < <(sort -n "$FEE_HISTORY_FILE")
    local n="${#arr[@]}"
    if [ "$n" -eq 0 ]; then echo ""; return; fi
    local idx
    idx=$(awk -v p="$p" -v n="$n" 'BEGIN{v=p/100.0*n; if (v<1) v=1; printf("%d",(v==int(v)?v:v+1))}')
    echo "${arr[$((idx-1))]}"
}

median_of_last_m() {
    local m="$1"
    [ ! -s "$FEE_HISTORY_FILE" ] && echo "" && return
    mapfile -t last < <(tail -n "$m" "$FEE_HISTORY_FILE" | sort -n)
    local n="${#last[@]}"
    if [ "$n" -eq 0 ]; then echo ""; return; fi
    local mid=$((n/2))
    if [ $((n % 2)) -eq 1 ]; then
        echo "${last[$mid]}"
    else
        # округляем вверх
        awk -v a="${last[$((mid-1))]}" -v b="${last[$mid]}" 'BEGIN{printf("%d", int(((a+b)/2.0)+0.9999))}'
    fi
}

compute_thresholds() {
    local static="$POPM_STATIC_FEE"
    local dyn="$static"
    if [ "$DYN_ENABLED" = "1" ]; then
        local px
        px=$(percentile_fee "$DYN_P")
        if [[ "$px" =~ ^[0-9]+$ ]]; then
            dyn="$px"
        fi
    fi
    local T_start
    if [ "$dyn" -lt "$static" ]; then T_start="$dyn"; else T_start="$static"; fi

    local stop_delta=$((T_start + HYST_DELTA))
    local stop_ratio
    stop_ratio=$(awk -v t="$T_start" -v r="$HYST_RATIO" 'BEGIN{printf("%d", (t*(1.0+r))+0.9999)}')
    local T_stop="$stop_delta"
    if [ "$stop_ratio" -gt "$T_stop" ]; then T_stop="$stop_ratio"; fi

    echo "$T_start $T_stop"
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

    # отслеживание окна после нового блока
    local last_tip=""
    local last_tip_time=0
    last_tip=$(get_tip_block)
    if [[ "$last_tip" =~ ^[0-9]+$ ]]; then last_tip_time=$(date +%s); fi

    local low_streak=0
    local low_since_ts=0

    while true; do
        # уважаем ожидание нового блока (вместо жёсткого кулдауна)
        if [ -f "$WAIT_NEXT_FLAG" ]; then
            log "Ожидание следующего блока перед новой попыткой..."
            rm -f "$WAIT_NEXT_FLAG"
            wait_for_new_block
            last_tip=$(get_tip_block); last_tip_time=$(date +%s)
            low_streak=0
        fi

        # газ
        gas_price=$(get_fastest_fee)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            log "Не удалось получить газ. Повтор через 30 сек..."
            sleep 30
            continue
        fi
        add_fee_sample "$gas_price"

        read T_START T_STOP < <(compute_thresholds)
        smooth_fee=$(median_of_last_m "$SMOOTH_M")
        [ -z "$smooth_fee" ] && smooth_fee="$gas_price"

        log "Газ: current=$gas_price, median=${smooth_fee} sat/vB; Пороги: старт=${T_START}, стоп=${T_STOP} (static=$POPM_STATIC_FEE, p${DYN_P}/N=${DYN_N})"

        # номер блока
        current_block=$(get_tip_block)
        if ! [[ "$current_block" =~ ^[0-9]+$ ]]; then
            log "Не удалось получить текущий блок. Повтор через 30 сек..."
            sleep 30
            continue
        fi
        # детект нового блока и окно
        if [ "$current_block" != "$last_tip" ]; then
            last_tip="$current_block"; last_tip_time=$(date +%s); low_streak=0
            log "Новый блок обнаружен в основном цикле: $current_block"
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

        # проверка окна после нового блока
        now_ts=$(date +%s)
        in_block_window=0
        if [ "$BLOCK_WINDOW_SEC" -le 0 ]; then in_block_window=1; else
            if [ $((now_ts - last_tip_time)) -le "$BLOCK_WINDOW_SEC" ]; then in_block_window=1; fi
        fi

        # streak по сглаженному значению
        if [ "$smooth_fee" -le "$T_START" ]; then
            low_streak=$((low_streak + 1))
            if [ "$low_since_ts" -eq 0 ]; then low_since_ts=$(date +%s); fi
        else
            low_streak=0
            low_since_ts=0
        fi

        # Доп. условие: длительно низкий газ вне окна блока
        long_ok=0
        if [ "$LONG_LOW_MINUTES" -gt 0 ] && [ "$low_since_ts" -gt 0 ]; then
            now_ts=$(date +%s)
            need=$((LONG_LOW_MINUTES*60))
            if [ $((now_ts - low_since_ts)) -ge "$need" ]; then long_ok=1; fi
        fi

        # проверка баланса перед запуском
        if ! balance_guard_or_wait; then
            sleep 30
            continue
        fi

        if { [ "$in_block_window" -eq 1 ] && [ "$low_streak" -ge "$START_STREAK_K" ]; } || [ "$long_ok" -eq 1 ]; then
            log "Газ в норме, запускаем майнер..."
            echo "$current_block" > "$LAST_BLOCK_FILE"
            ./popmd > "$LOG_FILE" 2>&1 &
            miner_pid=$!
            echo $miner_pid > "$PID_FILE"
            wait $miner_pid || true

            # Проверяем лог на успешную транзакцию и извлекаем TXID, если возможно
            if grep -q "PoP miner has shutdown cleanly" "$LOG_FILE" 2>/dev/null; then
                log "Успешная транзакция: майнер завершил работу корректно."
            fi
            txid=$(grep -Eoi '([a-f0-9]{64})' "$LOG_FILE" | tail -n1 || echo "")
            if [[ "$txid" =~ ^[a-f0-9]{64}$ ]]; then
                log "TXID: $txid"
                log "Ссылка: https://mempool.space/tx/$txid"
                send_tg "[HEMI] Успешная TX: $txid\nhttps://mempool.space/tx/$txid"
            fi

            # После завершения — ожидаем следующий блок, чтобы не повторять в том же блоке
            log "Завершили попытку на блок $current_block. Ждём следующий блок..."
            wait_for_new_block
            last_tip=$(get_tip_block); last_tip_time=$(date +%s); low_streak=0
        else
            if [ "$LONG_LOW_MINUTES" -gt 0 ] && [ "$low_since_ts" -gt 0 ]; then
                now_ts=$(date +%s); passed=$((now_ts - low_since_ts)); need=$((LONG_LOW_MINUTES*60))
                log "Условия старта не выполнены (window=${in_block_window}, streak=${low_streak}/${START_STREAK_K}, low_for=${passed}s/${need}s). Продолжаем ожидание..."
            else
                log "Условия старта не выполнены (window=${in_block_window}, streak=${low_streak}/${START_STREAK_K}). Продолжаем ожидание..."
            fi
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
        add_fee_sample "$gas_price"
        read T_START T_STOP < <(compute_thresholds)
        smooth_fee=$(median_of_last_m "$SMOOTH_M")
        [ -z "$smooth_fee" ] && smooth_fee="$gas_price"
        log "[монитор] Газ: current=$gas_price, median=${smooth_fee} sat/vB; Пороги: старт=${T_START}, стоп=${T_STOP}"
        if [ "$smooth_fee" -ge "$T_STOP" ]; then
            if [ -f "$PID_FILE" ]; then
                pid=$(cat "$PID_FILE" 2>/dev/null || echo "")
                if [ -n "$pid" ] && ps -p "$pid" >/dev/null 2>&1; then
                    log "[монитор] Газ > порога, останавливаем майнер (PID $pid)..."
                    kill "$pid" || true
                    # фиксируем текущий блок и просим основной цикл ждать следующий
                    tip=$(get_tip_block)
                    if [[ "$tip" =~ ^[0-9]+$ ]]; then echo "$tip" > "$LAST_BLOCK_FILE"; fi
                    touch "$WAIT_NEXT_FLAG"
                    log "[монитор] Установлено ожидание следующего блока"
                else
                    if pgrep -x popmd >/dev/null 2>&1; then
                        log "[монитор] Останавливаем popmd по имени процесса..."
                        pkill -x popmd || true
                        tip=$(get_tip_block)
                        if [[ "$tip" =~ ^[0-9]+$ ]]; then echo "$tip" > "$LAST_BLOCK_FILE"; fi
                        touch "$WAIT_NEXT_FLAG"
                    fi
                fi
            else
                if pgrep -x popmd >/dev/null 2>&1; then
                    log "[монитор] Останавливаем popmd по имени процесса..."
                    pkill -x popmd || true
                    tip=$(get_tip_block)
                    if [[ "$tip" =~ ^[0-9]+$ ]]; then echo "$tip" > "$LAST_BLOCK_FILE"; fi
                    touch "$WAIT_NEXT_FLAG"
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


