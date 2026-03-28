# 🦅 OPENCLAW

> **3-Agent Monte Carlo trading system on HyperEVM**  
> AI analysis → on-chain execution → automated exit strategy

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Python 3.11+](https://img.shields.io/badge/Python-3.11+-blue.svg)](https://python.org)
[![Solidity 0.8.20](https://img.shields.io/badge/Solidity-0.8.20-lightgrey.svg)](https://soliditylang.org)
[![HyperEVM](https://img.shields.io/badge/Network-HyperEVM-purple.svg)](https://hyperliquid.xyz)

---

## Come funziona

```
Tu digiti "HYPE" e premi HUNT
         │
         ▼
┌─────────────────────┐
│  AGENT_01 · BRAIN   │  10.000 simulazioni Monte Carlo
│  Monte Carlo Engine │  Analisi macro + volatilità storica
│                     │  Output: 73% probabilità long
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ AGENT_02 · EXECUTOR │  Decisione LONG / SHORT
│  Trade Executor     │  Kelly fraction + leverage ottimale
│                     │  Output: LONG 3x, kelly 12%, grade A+
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│ AGENT_03 · HARVESTER│  Piano di uscita completo
│  Profit Taker       │  TP1/TP2/TP3 ladder + stop-loss
│                     │  Output: R:R 1:3.4, exp ROI +22%
└──────────┬──────────┘
           │
           ▼
┌─────────────────────┐
│  EVM EXECUTOR       │  TX_01: executeSignal()   → apre posizione
│  OpenClawAgent.sol  │  TX_02: setExitStrategy() → arma TP + SL
│  HyperEVM Chain 999 │
└──────────┬──────────┘
           │
           ▼
  Hyperliquid L1 Exchange
  (via precompile 0x...0800)
```

---

## Struttura del progetto

```
openclaw/
├── contracts/
│   ├── src/
│   │   ├── OpenClawAgent.sol          # Smart contract principale
│   │   └── interfaces/
│   │       └── IHyperliquidExchange.sol  # Interfaccia precompile HL
│   ├── script/
│   │   └── DeployOpenClaw.s.sol       # Script di deploy (Foundry)
│   ├── test/
│   │   └── OpenClawAgent.t.sol        # Test unitari
│   └── foundry.toml
│
├── orchestrator/
│   ├── main.py                        # Entry point CLI
│   ├── agents.py                      # 3 agenti Claude
│   ├── evm.py                         # Interazione Web3 / HyperEVM
│   ├── config.py                      # Costanti e configurazione
│   └── requirements.txt
│
├── frontend/
│   ├── src/
│   │   └── App.jsx                    # UI React (3 agenti + EVM panel)
│   ├── index.html
│   ├── package.json
│   └── vite.config.js
│
├── docs/
│   └── architecture.md
│
├── .env.example
├── .gitignore
└── README.md
```

---

## Prerequisiti

| Tool | Versione | Uso |
|------|----------|-----|
| Python | 3.11+ | Orchestratore AI |
| Foundry | latest | Deploy contratto |
| Node.js | 18+ | Frontend |
| Anthropic API key | — | 3 agenti Claude |
| Wallet HyperEVM | — | Firma transazioni |

---

## Installazione

### 1. Clona il repository

```bash
git clone https://github.com/TUO_USERNAME/openclaw.git
cd openclaw
```

### 2. Configura le variabili d'ambiente

```bash
cp .env.example .env
# Modifica .env con i tuoi valori
```

### 3. Installa dipendenze Python

```bash
cd orchestrator
pip install -r requirements.txt
```

### 4. Installa dipendenze frontend

```bash
cd frontend
npm install
```

### 5. Installa Foundry (per il contratto)

```bash
curl -L https://foundry.paradigm.xyz | bash
foundryup
```

---

## Deploy del contratto

### Compila

```bash
cd contracts
forge build
```

### Testa

```bash
forge test -v
```

### Deploy su HyperEVM

```bash
forge script script/DeployOpenClaw.s.sol \
  --rpc-url https://rpc.hyperliquid.xyz/evm \
  --private-key $OPENCLAW_PRIVATE_KEY \
  --broadcast
```

Copia l'indirizzo del contratto deployato in `.env`:

```bash
OPENCLAW_CONTRACT=0x...
```

---

## Utilizzo

### Modalità dry run (default, nessuna transazione reale)

```bash
cd orchestrator
python main.py BTC --capital 1000
```

### Modalità live (transazioni reali su HyperEVM)

```bash
python main.py HYPE --capital 2000 --live
```

> ⚠️ In modalità `--live` viene richiesta conferma esplicita digitando `HUNT`.

### Avvia il frontend

```bash
cd frontend
npm run dev
# Apri http://localhost:5173
```

---

## Configurazione `.env`

```env
# AI
ANTHROPIC_API_KEY=sk-ant-...

# EVM
OPENCLAW_PRIVATE_KEY=0x...        # Wallet hot per HyperEVM
OPENCLAW_CONTRACT=0x...           # Indirizzo OpenClawAgent deployato
HYPER_EVM_RPC=https://rpc.hyperliquid.xyz/evm

# Parametri trading
DRY_RUN=true                       # false per eseguire transazioni reali
MIN_GRADE=B+                       # Soglia minima qualità trade (A+/A/B+/B/C)
MAX_LEVERAGE=5                     # Leva massima consentita
```

---

## Asset index Hyperliquid

| Symbol | Index | Symbol | Index |
|--------|-------|--------|-------|
| BTC    | 0     | AVAX   | 7     |
| ETH    | 1     | LINK   | 8     |
| SOL    | 2     | DOGE   | 9     |
| BNB    | 3     | WIF    | 11    |
| ARB    | 4     | HYPE   | 150   |
| OP     | 5     | TRUMP  | 14    |

> Verifica sempre gli indici aggiornati su [Hyperliquid docs](https://hyperliquid.gitbook.io).

---

## Architettura contratto

Il contratto `OpenClawAgent.sol` espone tre funzioni principali:

```solidity
// Apre posizione via precompile HyperEVM
function executeSignal(uint32 asset, bool isLong, uint8 leverage, uint64 sz) external onlyAgent

// Arma TP ladder + stop-loss (4 ordini reduce-only)
function setExitStrategy(uint32 asset, uint64 tp1, uint64 tp2, uint64 tp3, uint64 sl) external onlyAgent

// Chiude tutto in emergenza via market order
function emergencyClose(uint32 asset) external onlyAgent
```

Il contratto chiama il **precompile di Hyperliquid** all'indirizzo `0x0000000000000000000000000000000000000800` che instrada gli ordini direttamente al motore L1 dell'exchange.

---

## ⚠️ Avvertenze di sicurezza

- **Non committare mai il file `.env`** con chiavi private reali
- Usa un **wallet dedicato** con fondi limitati per l'agente — non il wallet principale
- Testa sempre in **dry run** prima di andare live
- Gli output AI sono **simulazioni probabilistiche**, non certezze
- Verifica sempre i prezzi TP/SL generati prima di eseguire
- **Non è consulenza finanziaria**

---

## License

MIT — vedi [LICENSE](LICENSE)
