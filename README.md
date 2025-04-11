---

# Installing the Miner on the HEMI Mainnet
![image](https://github.com/user-attachments/assets/a5f04dd4-2f30-4d51-93f1-7c71e7e6197d)

## ⚡ Important Note
Mining on the HEMI network is **not cheap** — the cost of running the miner is around **$200 per day**. (Make sure to catch low gas fees!)

## 📌 Requirements
You'll need a server to install the miner. You can rent one, for example, on [VDSina](https://www.vdsina.com/?partner=dd4tc21l55), which offers convenient daily payments.  
There are two installation methods:  
1. **Using a script** — for those who prefer a quick setup.  
2. **Manual installation** — for those who want to understand the process in detail.

### 🔧 Recommended Server Specs:
- **OS:** Ubuntu 20.04  
- **CPU:** 2 cores  
- **RAM:** 4 GB  
- **Storage:** 80 GB  

---

## 🚀 Creating a Wallet

1. Install **UniSat** and create a new wallet.
2. Fund your BTC balance (select **Legacy P2PKH** address type).
3. To fund your wallet, you can use [Symbiosis](https://app.symbiosis.finance/) (fee ~3$ via Ethereum network). Thanks to @jonnyboii for the tip.

---

## 🔧 Option 1: Installation via Script (Quick and Easy)

1. Download and run the script:
   ```bash
   wget -O install_gas.sh https://raw.githubusercontent.com/Dzmitryy1812/Miner-POP-HEMI-mainnet-/refs/heads/main/install%2Bgas.sh && chmod +x install_gas.sh && ./install_gas.sh
   ```

   ![image](https://github.com/user-attachments/assets/96b322fd-3042-460a-87a6-4cab4fbaeab3)

To get started, the script will ask you for two inputs:

1. **BTC Private Key** — your private key for the Bitcoin network.
2. **POPM_STATIC_FEE** — the gas fee value, which you can check at [mempool.space](https://mempool.space).

After that, the script will:
- Update your system
- Install required packages
- Download the miner
- Monitor the gas price, and once it falls below your specified threshold, it will launch the miner automatically

   ![image](https://github.com/user-attachments/assets/8c4d9e3b-0cca-46c6-bb1e-a6114a57edb4)

To stop the process, press `CTRL+C`.  
**Important:** The script only monitors gas **at startup**, not continuously.

---

## 🔧 Option 2: Manual Miner Installation

### 🔹 Update your system and install dependencies:
```sh
sudo apt update && sudo apt upgrade -y && sudo apt install wget unzip nano curl -y
```

### 🔹 Download the miner from the official GitHub:
```sh
wget https://github.com/hemilabs/heminetwork/releases/download/v1.0.0/heminetwork_v1.0.0_linux_amd64.tar.gz
```

### 🔹 Extract the archive:
```sh
tar -xvzf heminetwork_v1.0.0_linux_amd64.tar.gz
```

### 🔹 Install **screen** for background execution:
```sh
sudo apt install screen
```

Start a new screen session:
```sh
screen -S hemi_miner
```

### 🔹 Enter the miner directory:
```sh
cd heminetwork_v1.0.0_linux_amd64
```

### 🔹 Check the miner options:
```sh
./popmd --help
```

---

## 🛠️ Step 3. Miner Configuration

Set environment variables:
```sh
export POPM_BTC_PRIVKEY=your_private_key_here
export POPM_STATIC_FEE=4
export POPM_BFG_URL=wss://pop.hemi.network/v1/ws/public
export POPM_BTC_CHAIN_NAME=mainnet
```

**💡 You can find the current `POPM_STATIC_FEE` value at [mempool.space](https://mempool.space).**

---

## 🚴 Step 4. Start the Miner
```sh
./popmd
```

Congratulations! 🎉 Your miner is now live on the HEMI network.

---

## ❓ Frequently Asked Questions

### How to resume a screen session after disconnection?
```sh
screen -r hemi_miner
```

### How to stop the miner?
```sh
exit
```

### How to view your transactions?

Go to [mempool.space](https://mempool.space) and search using your **public BTC address**.

---

🔥 **Happy mining!** 🔥

---

Если нужно — могу сразу оформить этот гайд как `.md` файл для загрузки на GitHub.
