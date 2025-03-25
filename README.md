# Установка майнера в майнете HEMI

## ⚡ Важное замечание
Майнинг в сети HEMI — недешёвое удовольствие, стоимость работы майнера составляет около **200 долларов в сутки**.

## 📌 Требования
Для установки нам потребуется сервер. Можно арендовать, например, на [VDSina](https://www.vdsina.com/?partner=dd4tc21l55), где есть удобная посуточная оплата.

### 🔧 Рекомендуемые параметры сервера:
- **ОС:** Ubuntu 20.04  
- **Процессор:** 2 core  
- **Память:** 4 GB  
- **Хранилище:** 80 GB  

---

## 🚀 Шаг 1. Создание кошелька

1. Устанавливаем **UniSat** и создаем новый кошелек.
2. Пополняем баланс BTC (выбираем **Legacy P2PKH**).
3. Для пополнения можно воспользоваться [Symbiosis](https://app.symbiosis.finance/) (комиссия ~3$ в сети Ethereum). за информацию спасибо @jonnyboii 

---

## ⚙️ Шаг 2. Установка майнера на сервере

### 🔹 Обновляем среду и устанавливаем нужные пакеты:
```sh
sudo apt update && sudo apt upgrade -y && sudo apt install wget unzip nano curl -y
```

### 🔹 Скачиваем майнер с официального GitHub:
```sh
wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
```

### 🔹 Распаковываем архив:
```sh
tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
```

### 🔹 Устанавливаем **screen** для работы в фоновом режиме:
```sh
sudo apt install screen
```
Создаем новую сессию:
```sh
screen -S hemi_miner
```

### 🔹 Переходим в папку с майнером:
```sh
cd heminetwork_v1.0.0_linux_amd64
```

### 🔹 Проверяем конфигурационный файл:
```sh
./popmd --help
```

---

## 🛠️ Шаг 3. Настройка майнера

Редактируем конфигурацию:
```sh
export POPM_BTC_PRIVKEY=сюда_вставляем_приватный_ключ
export POPM_STATIC_FEE=4
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
```

**💡 Узнать текущее значение `POPM_STATIC_FEE` можно на [mempool.space](https://mempool.space).**

---

## 🚴 Шаг 4. Запуск майнера
```sh
./popmd
```

Поздравляем! 🎉 Теперь ваш майнер работает в сети HEMI.

---

## ❓ Частые вопросы

### Как возобновить сеанс screen, если отключился?
```sh
screen -r hemi_miner
```

### Как завершить работу майнера?
```sh
exit
```
### Как посмотреть транзакции?

[mempool](https://mempool.space)
и вставляем в поиск публичный ключ 
---

🔥 **Удачного майнинга!** 🔥


