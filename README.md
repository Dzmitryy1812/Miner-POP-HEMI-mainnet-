# Установка майнера в майнете HEMI
![image](https://github.com/user-attachments/assets/a5f04dd4-2f30-4d51-93f1-7c71e7e6197d)

## ⚡ Важное замечание
Майнинг в сети HEMI — недешёвое удовольствие, стоимость работы майнера составляет около **200 долларов в сутки**. (Ловите низкий газ)

## 📌 Требования
Для установки потребуется сервер. Можно арендовать, например, на [VDSina](https://www.vdsina.com/?partner=dd4tc21l55), где есть удобная посуточная оплата.  
Есть два варианта установки:  
1. **С помощью скрипта** — для ленивых.   
2. **Ручная установка** — для тех, кто хочет познать процесс майнинга в полной мере. 

### 🔧 Рекомендуемые параметры сервера:
- **ОС:** Ubuntu 20.04  
- **Процессор:** 2 core  
- **Память:** 4 GB  
- **Хранилище:** 80 GB  

---

## 🚀 Создание кошелька

1. Устанавливаем **UniSat** и создаем новый кошелек.
2. Пополняем баланс BTC (выбираем **Legacy P2PKH**).
3. Для пополнения можно воспользоваться [Symbiosis](https://app.symbiosis.finance/) (комиссия ~3$ в сети Ethereum). за информацию спасибо @jonnyboii 

---
## 🔧 Вариант 1: Установка через скрипт (быстро и просто)

1. Скачайте и выполните скрипт:
   ```bash
   wget -O install_gas.sh https://raw.githubusercontent.com/Dzmitryy1812/Miner-POP-HEMI-mainnet-/refs/heads/main/install%2Bgas.sh && chmod +x install_gas.sh && ./install_gas.sh
![image](https://github.com/user-attachments/assets/96b322fd-3042-460a-87a6-4cab4fbaeab3)


Для начала работы с майнером вам нужно будет ввести два параметра:

1. **Приватный ключ BTC** — ваш личный ключ для сети Bitcoin.
2. **POPM_STATIC_FEE** — значение комиссии за газ, которое можно узнать на [mempool.space](https://mempool.space).

После ввода этих данных скрипт автоматически:
- Обновит вашу систему,
- Установит все необходимые пакеты,
- Скачает майнер,
- И будет ожидать, когда цена газа опустится до указанного вами значения, после чего автоматически запустит майнер.
![image](https://github.com/user-attachments/assets/8c4d9e3b-0cca-46c6-bb1e-a6114a57edb4)


Для остановки процесса используется команда CTRL+C.
Важно!! Скрипт мониторит газ только при запуске. 
## 🔧 Вариант 2: Установка майнера на сервере (ручной способ)

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


