# OPENCLAW — Guida passo per passo

Tempo totale stimato: ~45 minuti
Difficoltà: intermedia

---

## COSA TI SERVE PRIMA DI INIZIARE

| Cosa | Dove ottenerlo | Costo |
|------|---------------|-------|
| Anthropic API key | platform.anthropic.com | pay-per-use |
| MetaMask installato | metamask.io | gratis |
| Python 3.11+ | python.org | gratis |
| Node.js 18+ | nodejs.org | gratis |
| HYPE per il gas | Hyperliquid bridge | ~1-2 HYPE |

---

## FASE 1 — WALLET E RETE HYPEREVM

### 1.1 — Aggiungi HyperEVM a MetaMask

Apri MetaMask → Aggiungi rete → inserisci questi dati:

```
Nome rete:       HyperEVM
RPC URL:         https://rpc.hyperliquid.xyz/evm
Chain ID:        999
Simbolo:         HYPE
Block explorer:  https://hyperevm-explorer.hyperliquid.xyz
```

### 1.2 — Crea un wallet DEDICATO per l'agente

⚠️ NON usare il tuo wallet principale.
Crea un wallet nuovo in MetaMask → copia l'indirizzo e la private key.

Questo wallet ha bisogno di:
- Un po' di HYPE per pagare il gas su HyperEVM (0.1 HYPE è sufficiente per molte tx)
- NON ha bisogno di collaterale — il contratto opera sul tuo account HL, non su fondi propri

### 1.3 — Deposita HYPE per il gas

Su Hyperliquid → Trasferisci → scegli "Deposit to HyperEVM" → manda 0.5 HYPE
all'indirizzo del wallet agente appena creato.

---

## FASE 2 — DEPLOY DEL CONTRATTO CON REMIX IDE

### 2.1 — Apri Remix

Vai su https://remix.ethereum.org nel browser dove hai MetaMask.

### 2.2 — Crea la struttura file

Nel pannello di sinistra (File Explorer) clicca l'icona cartella per creare:

```
contracts/
├── interfaces/
│   └── IHyperliquidExchange.sol
└── OpenClawAgent.sol
```

Per creare una cartella: clic destro su "contracts" → New Folder → scrivi "interfaces"
Per creare un file: clic destro sulla cartella → New File → scrivi il nome

### 2.3 — Incolla il codice

**File: `interfaces/IHyperliquidExchange.sol`**
Apri il file → incolla tutto il contenuto di `contracts/src/interfaces/IHyperliquidExchange.sol`

**File: `OpenClawAgent.sol`**
Apri il file → incolla tutto il contenuto di `contracts/src/OpenClawAgent.sol`

⚠️ In `OpenClawAgent.sol` aggiorna l'import nella prima riga:
```solidity
// Cambia questa riga:
import "./interfaces/IHyperliquidExchange.sol";
// In Remix il path relativo funziona così
```

### 2.4 — Compila

Nel pannello di sinistra clicca l'icona del compilatore (quadrato con una S).

- Versione compilatore: **0.8.20**
- Spunta "Optimization" → 200 runs
- Clicca **"Compile OpenClawAgent.sol"**

Se vedi pallino verde = tutto ok. Se ci sono errori di import, verifica i path.

### 2.5 — Connetti MetaMask a HyperEVM

Nel pannello Deploy (icona con freccia in basso):
- Environment: **"Injected Provider - MetaMask"**
- MetaMask si aprirà → seleziona il wallet agente → assicurati che la rete sia HyperEVM (Chain ID 999)

Se MetaMask non propone HyperEVM, torna al passo 1.1.

### 2.6 — Deploy

Ancora nel pannello Deploy:

1. **Contract**: seleziona `OpenClawAgent`
2. Accanto a "Deploy" c'è un campo per il costruttore → inserisci:
   ```
   _aiAgent: 0xTUO_INDIRIZZO_WALLET_AGENTE
   ```
   (stesso indirizzo del wallet che hai creato al passo 1.2)
3. Clicca **"Deploy"**
4. MetaMask chiede conferma → Confirm

Aspetta qualche secondo. In basso a destra nella console di Remix apparirà:
```
✅ [block: X] from: 0x... to: OpenClawAgent.(constructor)
```

### 2.7 — Copia l'indirizzo del contratto

In basso nel pannello Deploy, sotto "Deployed Contracts", appare:
```
OPENCLAWAGENT AT 0xABC123...
```

**Copia questo indirizzo** — ti serve nel passo successivo.

---

## FASE 3 — ORCHESTRATORE PYTHON

### 3.1 — Estrai il progetto

```bash
unzip openclaw_repo.zip
cd openclaw/orchestrator
```

### 3.2 — Crea l'ambiente virtuale

```bash
python -m venv venv

# macOS/Linux:
source venv/bin/activate

# Windows:
venv\Scripts\activate
```

### 3.3 — Installa le dipendenze

```bash
pip install -r requirements.txt
```

Installa: `anthropic`, `web3`, `eth-account`, `python-dotenv`, `rich`

### 3.4 — Configura il file .env

```bash
cp ../.env.example .env
```

Apri `.env` con un editor e compila:

```env
# La tua API key Anthropic (da platform.anthropic.com → API Keys)
ANTHROPIC_API_KEY=sk-ant-XXXXXXXXXXXX

# La private key del wallet agente creato al passo 1.2
# (in MetaMask: tre puntini → Account details → Show private key)
OPENCLAW_PRIVATE_KEY=0xXXXXXXXXXXXXXXXX

# L'indirizzo del contratto copiato al passo 2.7
OPENCLAW_CONTRACT=0xXXXXXXXXXXXXXXXX

# Lascia questi così com'è
HYPER_EVM_RPC=https://rpc.hyperliquid.xyz/evm
DRY_RUN=true
MIN_GRADE=B+
MAX_LEVERAGE=5
CLAUDE_MODEL=claude-sonnet-4-6
```

⚠️ **Non committare mai `.env` su GitHub.**
Il `.gitignore` già lo esclude, ma fai attenzione.

### 3.5 — Test dry run

```bash
python main.py BTC --capital 1000
```

Vedrai i 3 agenti lavorare in sequenza. Alla fine mostra le transazioni che
VERREBBERO inviate, senza inviarle davvero.

Se tutto funziona, output simile a:

```
AGENT_01 · THE BRAIN · Monte Carlo Engine
  Bull prob  73%
  Bear prob  27%
  Regime     BULL

AGENT_02 · THE EXECUTIONER · Trade Executor
  ┌──────────────────────────────────┐
  │ ▲ LONG  Grade:A+  Kelly:12.4%   │
  └──────────────────────────────────┘

AGENT_03 · THE HARVESTER · Profit Taker
  TP1  +8%   close 33%
  TP2  +15%  close 33%
  TP3  +25%  close 33%
  STOP -5%   exit 100%

TX_01 · executeSignal()  [DRY RUN]
TX_02 · setExitStrategy() [DRY RUN]

✅ HUNT COMPLETE
```

### 3.6 — Prova su altri asset

```bash
python main.py HYPE --capital 500
python main.py ETH  --capital 2000
python main.py SOL  --capital 300
```

---

## FASE 4 — FRONTEND (opzionale)

### 4.1 — Installa dipendenze

```bash
cd ../frontend
npm install
```

### 4.2 — Avvia in sviluppo

```bash
npm run dev
```

Apri http://localhost:5173 — trovi l'interfaccia grafica completa.
Funziona anche senza il Python, chiama direttamente l'API Anthropic dal browser.

---

## FASE 5 — MODALITÀ LIVE (transazioni reali)

Solo quando hai fatto almeno 5-10 dry run e sei sicuro del funzionamento:

### 5.1 — Metti DRY_RUN=false nel .env

```env
DRY_RUN=false
```

Oppure usa il flag `--live` da CLI (non richiede di modificare .env):

### 5.2 — Esegui con conferma esplicita

```bash
python main.py HYPE --capital 500 --live
```

Il sistema chiede:
```
⚠  MODALITÀ LIVE — le transazioni verranno inviate realmente.
Digita 'HUNT' per confermare:
```

Scrivi `HUNT` e premi invio.

Le due transazioni vengono firmate e inviate:
- **TX_01** → apre la posizione su Hyperliquid
- **TX_02** → arma TP1, TP2, TP3 e stop-loss

Da questo momento il contratto gestisce tutto automaticamente.
Puoi chiudere il terminale — gli ordini sono on-chain.

---

## PROBLEMI COMUNI

### "OPENCLAW_CONTRACT non configurata"
Hai dimenticato di mettere l'indirizzo del contratto in `.env`

### "Asset 'XXX' non trovato in ASSET_INDEX"
L'asset non è nella lista in `config.py`. Aggiungilo:
```python
ASSET_INDEX["XXX"] = 999  # trova l'indice corretto su HL docs
```

### Errore di compilazione in Remix: "File not found"
Verifica che il path dell'import sia corretto. In Remix usa:
```solidity
import "./interfaces/IHyperliquidExchange.sol";
```

### MetaMask non mostra HyperEVM
Torna al passo 1.1 e aggiungi la rete manualmente.
Chain ID 999 è fondamentale — senza quello non funziona.

### "Execution reverted" sulla TX
- Controlla che il wallet abbia HYPE per il gas
- Controlla che `msg.sender` sia l'indirizzo `aiAgent` impostato nel costruttore
- Se hai impostato un `aiAgent` diverso dal deployer, assicurati di usare quella private key in `.env`

### Il dry run funziona ma il live no
- Verifica che `OPENCLAW_PRIVATE_KEY` corrisponda al wallet con HYPE per il gas
- Verifica che quell'indirizzo sia l'`aiAgent` del contratto

---

## CHECKLIST FINALE

Prima di andare live spunta tutto:

- [ ] Wallet agente creato e separato dal principale
- [ ] HYPE depositato sul wallet agente (per il gas)
- [ ] Contratto deployato su HyperEVM con Remix
- [ ] Indirizzo contratto copiato in `.env`
- [ ] Dry run completato almeno 5 volte senza errori
- [ ] `MIN_GRADE=B+` o superiore impostato (non tradare grade C)
- [ ] `MAX_LEVERAGE` impostato a un valore che tolleri
- [ ] File `.env` NON committato su GitHub
