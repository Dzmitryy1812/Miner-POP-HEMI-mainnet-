#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.6.3_linux_amd64"
CONFIG_FILE="$MINER_DIR/config.sh"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "Ошибка: Скрипт должен быть запущен с правами root (используйте sudo)."
    exit 1
fi

# Список необходимых пакетов
PACKAGES="jq curl wget unzip nano"

# Функция установки пакетов
install_packages() {
    echo "Проверка необходимых пакетов..."
    for pkg in $PACKAGES; do
        if ! dpkg -l | grep -q " $pkg "; then
            echo "$pkg не найден, устанавливаем..."
            apt update
            apt install -y "$pkg"
            if [ $? -ne 0 ]; then
                echo "Ошибка: Не удалось установить $pkg."а
                exit 1
            fi
        fi
    done
}

install_packages

# Проверка установки майнера
if [ -d "$MINER_DIR" ]; then
    echo "Майнер уже установлен, пропускаем установку."
else
    echo "Майнер не найден, начинаем установку..."
    apt update && apt upgrade -y
    wget https://github.com/hemilabs/heminetwork/releases/download/v1.6.3/heminetwork_v1.6.3_linux_amd64.tar.gz
    tar -xvzf heminetwork_v1.6.3_linux_amd64.tar.gz
fi

# Настройка конфига
echo ""
echo "===== Настройка майнера ====="
read -p "Введите ваш приватный ключ BTC: " btc_key
read -p "Введите POPM_STATIC_FEE (например 4): " static_fee
if ! [[ "$static_fee" =~ ^[0-9]+$ ]]; then
    echo "Ошибка: POPM_STATIC_FEE должен быть числом!"
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
source "$CONFIG_FILE"

# Функция запуска майнера с ограничением одной транзакции
start_miner_single_tx() {
    while true; do
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка: Не удалось получить данные о газе. Повтор через 30 секунд..."
            sleep 30
            continue
        fi
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Газ: $gas_price sat/vB (Порог: $POPM_STATIC_FEE sat/vB)"

        if [ "$gas_price" -le "$POPM_STATIC_FEE" ]; then
            echo "Газ в норме, запускаем майнер..."
            
            # Создаем временный файл для логов
            LOG_FILE="/tmp/popmd_$$.log"
            
            # Запускаем майнер с перенаправлением логов и выводом в консоль
            cd "$MINER_DIR" && source "$CONFIG_FILE" && ./popmd 2>&1 | tee "$LOG_FILE" & 
            miner_pid=$!
            
            # Ждем завершения майнера (мониторинг будет управлять остановкой)
            wait $miner_pid
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Майнер завершил работу."
            
            # Короткая пауза перед следующей проверкой газа
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Короткая пауза перед следующей проверкой..."
            sleep 30  # 30 секунд вместо 10 минут
        else
            echo "Газ слишком высокий, продолжаем ожидание..."
            sleep 30
        fi
    done
}

# Обработчик Ctrl+C
cleanup() {
    echo "Прерывание скрипта..."
    pkill -f "popmd"
    exit 0
}
trap cleanup INT

# Старт
start_miner_single_tx
