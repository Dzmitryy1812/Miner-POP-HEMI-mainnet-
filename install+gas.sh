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
        if dpkg -l | grep -q " $pkg "; then
            echo "$pkg уже установлен."
        else
            echo "$pkg не найден, устанавливаем..."
            sudo apt update
            sudo apt install -y "$pkg"
            if [ $? -ne 0 ]; then
                echo "Ошибка: Не удалось установить $pkg."
                exit 1
            fi
        fi
    done
}

# Установка пакетов
install_packages

# Проверка установки майнера
if [ -d "$MINER_DIR" ]; then
    echo "Майнер уже установлен, пропускаем установку."
else
    echo "Майнер не найден, начинаем установку..."
    sudo apt update && sudo apt upgrade -y
    wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
    if [ $? -ne 0 ]; then
        echo "Ошибка: Не удалось скачать файл."
        exit 1
    fi
    tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
    if [ $? -ne 0 ]; then
        echo "Ошибка: Не удалось разархивировать файл."
        exit 1
    fi
    # Проверка и переход в директорию майнера
    if [ -d "$MINER_DIR" ]; then
        cd "$MINER_DIR" || {
            echo "Ошибка: Не удалось перейти в директорию $MINER_DIR."
            exit 1
        }
    else
        echo "Ошибка: Директория майнера $MINER_DIR не существует."
        exit 1
    fi
fi

# --- Функция очистки при прерывании ---
cleanup() {
    echo "Прерывание скрипта..."
    if pgrep -f "popmd" > /dev/null; then
        echo "Останавливаем майнер..."
        pkill -f "popmd"
    fi
    echo "Выход..."
    exit 0
}

# Устанавливаем обработчик прерывания (Ctrl+C)
trap cleanup INT

# --- Настройка конфига при каждом запуске скрипта ---
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
echo "---------------------------"
cat "$CONFIG_FILE"
echo "---------------------------"

# Загружаем параметры из нового конфига
source "$CONFIG_FILE"

# --- Ожидание подходящего газа для запуска майнера ---
echo "Ожидаем газ ниже или равный $POPM_STATIC_FEE... для запуска майнера."
while true; do
    gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
    if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
        echo
