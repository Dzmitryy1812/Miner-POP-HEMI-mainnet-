#!/bin/bash

echo "=== HEMI Miner Installer ==="

# Установка Node.js
echo "Устанавливаем Node.js..."
curl -fsSL https://deb.nodesource.com/setup_16.x | sudo -E bash -
sudo apt install -y nodejs

# Проверка установки Node.js
node -v
npm -v

# Установка майнера, если он еще не установлен
if [ ! -d "heminetwork_v1.0.0_linux_amd64" ]; then
    sudo apt update && sudo apt upgrade -y
    sudo apt install wget unzip nano curl screen -y

    wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
    tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
    cd heminetwork_v1.0.0_linux_amd64
else
    echo "Майнер уже установлен."
    cd heminetwork_v1.0.0_linux_amd64
fi

# --- Меню ---

echo ""
echo "===== Настройка майнера ====="
read -p "Введите ваш приватный ключ BTC: " btc_key
read -p "Введите POPM_STATIC_FEE (например 4): " static_fee

# --- Генерация конфига ---
cat > config.sh <<EOF
export POPM_BTC_PRIVKEY=${btc_key}
export POPM_STATIC_FEE=${static_fee}
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
EOF

chmod +x config.sh

echo ""
echo "✅ Конфиг успешно создан!"
cat config.sh
echo "---------------------------"

# Функция для получения текущего газа
get_gas_price() {
    node -e "
const https = require('https');
https.get('https://api.blockchair.com/bitcoin/stats', (res) => {
    let data = '';
    res.on('data', (chunk) => { data += chunk; });
    res.on('end', () => {
        const gasPrice = JSON.parse(data).data.transaction_stats.gas_price;
        console.log('Текущий газ: ' + gasPrice);
    });
});
"
}

# --- Меню выбора ---

while true; do
    echo ""
    get_gas_price
    echo ""
    echo "1) Запустить майнер"
    echo "2) Редактировать конфиг (nano)"
    echo "3) Выход"
    read -p "Выберите действие: " choice
    case $choice in
        1) source config.sh && ./popmd ;;
        2) nano config.sh ;;
        3) exit ;;
        *) echo "Неверный ввод!";;
    esac
done
