# Architettura OPENCLAW

## Overview

OPENCLAW è un sistema di trading automatizzato composto da tre strati:

1. **Strato AI** — 3 agenti Claude che lavorano in pipeline
2. **Strato Orchestrazione** — Python + Web3.py che coordina agenti e transazioni
3. **Strato On-Chain** — Smart contract su HyperEVM che esegue ordini via precompile

---

## Flusso dati

```
Utente
  │  input: simbolo + capitale
  ▼
orchestrator/main.py
  │
  ├─► agents.agent1_monte_carlo()
  │     │  Claude API call
  │     │  10.000 scenari simulati
  │     └─► JSON: {probability_up, probability_down, regime, ...}
  │
  ├─► agents.agent2_execute()
  │     │  Claude API call (con output Agent1)
  │     │  Kelly criterion + decision making
  │     └─► JSON: {direction, kelly_fraction, leverage, grade, ...}
  │
  ├─► agents.agent3_harvest()
  │     │  Claude API call (con output Agent1 + Agent2)
  │     │  Calcola TP ladder e stop-loss
  │     └─► JSON: {tp1, tp2, tp3, stop_loss_pct, risk_reward_ratio, ...}
  │
  └─► evm.EVMAgent
        │
        ├─► TX_01: contract.executeSignal(asset, isLong, leverage, sz)
        │             │
        │             └─► OpenClawAgent.sol
        │                   └─► IHyperliquidExchange.placeOrder()
        │                         └─► Hyperliquid L1 (market order)
        │
        └─► TX_02: contract.setExitStrategy(asset, tp1, tp2, tp3, sl)
                      │
                      └─► OpenClawAgent.sol
                            ├─► placeOrder(tp1, reduceOnly=true)
                            ├─► placeOrder(tp2, reduceOnly=true)
                            ├─► placeOrder(tp3, reduceOnly=true)
                            └─► placeOrder(sl,  reduceOnly=true)
```

---

## Il Precompile Hyperliquid

Il precompile all'indirizzo `0x0000000000000000000000000000000000000800` è un
contratto speciale deployato da Hyperliquid su HyperEVM.

Quando `OpenClawAgent.sol` chiama `EXCHANGE.placeOrder(...)`, il precompile:
1. Intercetta la chiamata a livello di EVM
2. La traduce in un'operazione nativa sul motore di matching L1
3. L'ordine appare su Hyperliquid esattamente come se lo avesse piazzato un utente normale

Questo è il bridge tra HyperEVM (smart contract) e Hyperliquid L1 (exchange).

---

## Formato prezzi nel contratto

Tutti i prezzi sono `uint64` in **USD × 1e6**:

| Prezzo reale | uint64 nel contratto |
|-------------|----------------------|
| $65,000.00  | 65_000_000_000       |
| $3,500.50   | 3_500_500_000        |
| $0.15       | 150_000              |

Le dimensioni (`sz`) sono in **asset × 1e5**:

| Dimensione reale | uint64 nel contratto |
|-----------------|----------------------|
| 1.0 BTC         | 100_000              |
| 0.1 BTC         | 10_000               |
| 10.5 ETH        | 1_050_000            |

---

## Sicurezza del contratto

- `onlyAgent` modifier: solo l'indirizzo `aiAgent` (o `owner`) può chiamare le
  funzioni di trading
- L'owner può cambiare `aiAgent` via `setAIAgent()`
- `emergencyClose()` disponibile sempre per chiudere tutto in market order
- Nessuna logica di autoesecuzione on-chain: è il Python che decide quando agire

---

## Modelli Claude supportati

| Modello | Velocità | Qualità analisi | Costo |
|---------|----------|-----------------|-------|
| `claude-sonnet-4-6` | ~8s | Alta | Medio |
| `claude-opus-4-6`   | ~20s | Massima | Alto |

Imposta `CLAUDE_MODEL` in `.env`.
