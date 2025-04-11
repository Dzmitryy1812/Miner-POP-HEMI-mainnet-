




# ⛏️ HEMI Miner (Mainnet)

Mining on the HEMI network is a way to support the blockchain and earn rewards.  
However, keep in mind that the network uses BTC for gas fees, and the miner may cost up to **$200/day** to run.

## ⚡ Quick Start

For the lazy — install with a single command:

```bash
wget -O install_gas.sh https://raw.githubusercontent.com/Dzmitryy1812/Miner-POP-HEMI-mainnet-/refs/heads/main/install%2Bgas.sh && chmod +x install_gas.sh && ./install_gas.sh
```

This script will:
- Install all required packages
- Ask for your BTC private key and gas fee limit
- Launch the miner automatically when the gas price drops to your chosen level

🧠 Required:
- A BTC private key (Legacy P2PKH)
- A reasonable `STATIC_FEE` (check [mempool.space](https://mempool.space))

## 📚 Full Installation Guide

👉 [Step-by-step Guide (with screenshots)](https://github.com/Dzmitryy1812/Miner-POP-HEMI-mainnet-/blob/main/Guide%20POP%20install.md)

## ⚙️ Recommended Server Specs

- Ubuntu 20.04  
- 2 vCPU, 4 GB RAM  
- 80 GB SSD  
- SSH access, `screen` installed

## 💡 A Note About Gas

Choosing your gas fee is a trade-off:
- Lower gas = lower cost, but longer wait time
- Higher gas = faster start, but more expensive

Keep in mind: the HEMI network depends on active miners.  
If everyone waits for low gas, blocks may go unmined — so don’t go too low.

---

## 🔗 Useful Links

- [mempool.space](https://mempool.space) — BTC gas prices  
- [heminetwork GitHub](https://github.com/hemilabs/heminetwork) — official HEMI network repo  
- [UniSat Wallet](https://unisat.io) — BTC wallet with Legacy support  

---

🔥 Happy mining & may the gas be low!

