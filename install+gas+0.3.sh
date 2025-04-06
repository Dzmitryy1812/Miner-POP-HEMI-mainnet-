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
read -p "Введите газ, который следует ждать (например 1): " gas_to_wait
read -p "Введите газ, который следует установить в файле (например 1.3): " gas_to_set

# Проверка, что оба значения числовые
if ! [[ "$gas_to_wait" =~ ^[0-9]+$ ]] || ! [[ "$gas_to_set" =~ ^[0-9]+(\.[0-9]+)?$ ]]; then
    echo "Ошибка: Значения газа должны быть числами!"
    exit 1
fi

# Обновление конфигурационного файла с заданным значением газа
cat > "$CONFIG_FILE" <<EOF
#!/bin/bash
export POPM_BTC_PRIVKEY=${btc_key}
export POPM_STATIC_FEE=${gas_to_set}
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
EOF
chmod +x "$CONFIG_FILE"
echo "✅ Конфиг обновлен! Установлена комиссия: $gas_to_set sat/vB"
source "$CONFIG_FILE"

# Функция для запуска майнера с проверкой газа
start_miner() {
    while true; do
        # Получаем текущую цену газа
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        
        # Проверяем, что получена корректная цена
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Ошибка: Не удалось получить данные о газе. Повтор через 30 секунд..."
            sleep 30
            continue
        fi

        # Печатаем текущую цену газа и порог для майнера
        echo "$(date '+%Y-%m-%d %H:%M:%S') - Газ: $gas_price sat/vB (Порог для ожидания: $gas_to_wait sat/vB)"
        
        # Сравниваем газ с порогом для ожидания
        if [ "$gas_price" -le "$gas_to_wait" ]; then
            echo "Газ в норме, запускаем майнер..."

            # Здесь мы устанавливаем газ для майнера в конфиге
            sed -i "s/^export POPM_STATIC_FEE=.*$/export POPM_STATIC_FEE=${gas_to_set}/" "$CONFIG_FILE"

            # Запускаем майнер с обновленной комиссией
            cd "$MINER_DIR" && source "$CONFIG_FILE" && ./popmd &

            # Запоминаем PID майнера
            miner_pid=$!
            wait $miner_pid
            echo "$(date '+%Y-%m-%d %H:%M:%S') - Майнер завершил работу. Перезапуск через 10 минут..."
            sleep 600  # 10 минутный таймаут
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
