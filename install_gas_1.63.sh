#!/bin/bash

# Параметры
MINER_DIR="$HOME/heminetwork_v1.0.0_linux_amd64"
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
                echo "Ошибка: Не удалось установить $pkg."
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
    wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
    tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
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

# Функция ожидания нового блока
wait_for_new_block() {
    last_block=$(curl -s https://mempool.space/api/v1/blocks/tip/height 2>/dev/null)
    if ! [[ "$last_block" =~ ^[0-9]+$ ]]; then
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка: Не удалось получить номер блока. Повтор через 30 секунд..."
        sleep 30
        wait_for_new_block
        return
    fi
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Ожидание нового блока..."
    while true; do
        current_block=$(curl -s https://mempool.space/api/v1/blocks/tip/height 2>/dev/null)
        if [[ "$current_block" =~ ^[0-9]+$ ]] && [ "$current_block" -gt "$last_block" ]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Новый блок $current_block обнаружен."
            break
        fi
        sleep 10
    done
}

# Функция запуска майнера с проверкой газа и ожиданием нового блока
start_miner() {
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
            cd "$MINER_DIR" && source "$CONFIG_FILE" && ./popmd > miner_output.log 2>&1
            # Проверяем вывод майнера на успешное завершение
            if grep -q "PoP miner has shutdown cleanly" miner_output.log; then
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Майнер завершил работу с успешной транзакцией. Ожидаем новый блок..."
                wait_for_new_block
            else
                echo "$(date '+%Y-%m-%d %H:%M:%S') - Майнер завершил работу без успешной транзакции. Повтор через 30 секунд..."
                sleep 30
            fi
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
start_miner
