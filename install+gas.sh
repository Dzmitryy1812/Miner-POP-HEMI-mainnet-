#!/bin/bash

# Параметры
VERSION="v1.0.0"
ARCHIVE="heminetwork_${VERSION}_linux_amd64.tar.gz"
FOLDER="heminetwork_${VERSION}_linux_amd64"
MINER_DIR="$HOME/$FOLDER"
CONFIG_FILE="$MINER_DIR/config.sh"

# Проверка прав root
if [ "$EUID" -ne 0 ]; then
    echo "❌ Ошибка: Скрипт должен быть запущен с правами root (используйте sudo)."
    exit 1
fi

# Список необходимых пакетов
PACKAGES="jq curl wget unzip nano"

# Функция установки пакетов
install_packages() {
    echo "🔍 Проверка необходимых пакетов..."
    for pkg in $PACKAGES; do
        if ! dpkg -l | grep -q " $pkg "; then
            echo "➕ $pkg не найден, устанавливаем..."
            apt update && apt install -y "$pkg"
            if [ $? -ne 0 ]; then
                echo "❌ Ошибка: Не удалось установить $pkg."
                exit 1
            fi
        fi
    done
}

install_packages

# Установка майнера
if [ -d "$MINER_DIR" ]; then
    echo "✅ Майнер уже установлен, пропускаем установку."
else
    echo "⬇️ Скачиваем и устанавливаем майнер $VERSION..."
    cd "$HOME"
    wget -q --show-progress "https://github.com/hemilabs/heminetwork/releases/download/${VERSION}/${ARCHIVE}"
    tar -xzf "$ARCHIVE"
    rm "$ARCHIVE"
    chmod +x "$MINER_DIR/popmd"
fi

# Настройка конфига
echo ""
echo "===== ⚙️ Настройка майнера ====="
read -p "Введите ваш приватный ключ BTC: " btc_key
read -p "Введите POPM_STATIC_FEE (например 4): " static_fee
if ! [[ "$static_fee" =~ ^[0-9]+$ ]]; then
    echo "❌ Ошибка: POPM_STATIC_FEE должен быть числом!"
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
source "$CONFIG_FILE"
echo "✅ Конфиг обновлен!"

# Функция запуска майнера с проверкой газа
start_miner() {
    while true; do
        gas_price=$(curl -s https://mempool.space/api/v1/fees/recommended | jq -r '.fastestFee' 2>/dev/null)
        if [ -z "$gas_price" ] || ! [[ "$gas_price" =~ ^[0-9]+$ ]]; then
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ⚠️ Ошибка получения газа. Повтор через 30 секунд..."
            sleep 30
            continue
        fi

        echo "$(date '+%Y-%m-%d %H:%M:%S') - Газ: $gas_price sat/vB (Порог: $POPM_STATIC_FEE sat/vB)"

        if [ "$gas_price" -le "$POPM_STATIC_FEE" ]; then
            echo "✅ Газ в норме, запускаем майнер..."
            cd "$MINER_DIR" && nohup ./popmd > miner.log 2>&1 &
            miner_pid=$!
            wait $miner_pid
            echo "$(date '+%Y-%m-%d %H:%M:%S') - ℹ️ Майнер завершил работу. Перезапуск через 10 минут..."
            sleep 600
        else
            echo "⏳ Газ слишком высокий, ждём 30 секунд..."
            sleep 30
        fi
    done
}

# Обработчик Ctrl+C
cleanup() {
    echo "🛑 Прерывание скрипта..."
    pkill -f "popmd"
    exit 0
}
trap cleanup INT

# Старт
start_miner
