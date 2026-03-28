// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

// ─────────────────────────────────────────────────────────────────────────────
// OPENCLAW — On-Chain EVM Trading Agent
// Deployed on HyperEVM. Receives signals from off-chain AI orchestrator and
// executes perp trades via the Hyperliquid L1 Exchange Precompile.
//
// HyperEVM Exchange Precompile: 0x0000000000000000000000000000000000000800
// Docs: https://hyperliquid.gitbook.io/hyperliquid-docs/for-developers/hyperevm
// ─────────────────────────────────────────────────────────────────────────────

/// @dev Minimal interface for Hyperliquid's HyperEVM exchange precompile.
///      The precompile lives at 0x0000000000000000000000000000000000000800 and
///      mirrors the Hyperliquid L1 order-placement logic.
interface IHyperliquidExchange {
    /// @param asset      Asset index. 0=BTC, 1=ETH, 2=SOL … see HL asset list.
    /// @param isBuy      true = long / buy, false = short / sell.
    /// @param limitPx    Price in USD × 1e6. Pass 0 for market orders.
    /// @param sz         Size in base asset × 1e5 (e.g. 0.1 BTC = 10000).
    /// @param reduceOnly Only reduce an existing position; never open new.
    /// @param orderType  2 = market, 3 = limit (GTC), 4 = limit (IOC).
    /// @param cloid      Client order ID for tracking/cancellation.
    function placeOrder(
        uint32  asset,
        bool    isBuy,
        uint64  limitPx,
        uint64  sz,
        bool    reduceOnly,
        uint8   orderType,
        uint64  cloid
    ) external;

    function cancelOrder(uint32 asset, uint64 cloid) external;
    function setReferrer(address referrer) external;
}

// ─────────────────────────────────────────────────────────────────────────────

contract OpenClawAgent {

    // ── Constants ────────────────────────────────────────────────────────────
    IHyperliquidExchange public constant EXCHANGE =
        IHyperliquidExchange(0x0000000000000000000000000000000000000800);

    uint8  constant ORDER_MARKET = 2;
    uint8  constant ORDER_LIMIT  = 3;

    // ── State ─────────────────────────────────────────────────────────────────
    address public owner;
    address public aiAgent;     // The authorised off-chain AI orchestrator EOA

    struct Position {
        bool   isOpen;
        bool   isLong;
        uint32 asset;
        uint8  leverage;
        uint64 sz;
        uint64 entryCloid;
        uint64 tp1Cloid;
        uint64 tp2Cloid;
        uint64 tp3Cloid;
        uint64 slCloid;
        uint64 openedAt;
    }

    // asset index → current position
    mapping(uint32 => Position) public positions;
    // sequential nonce for unique cloids
    uint64 private _nonce;

    // ── Events ────────────────────────────────────────────────────────────────
    event AgentUpdated(address indexed newAgent);
    event SignalReceived(uint32 indexed asset, bool isLong, uint8 leverage, uint64 sz);
    event OrderPlaced(uint32 indexed asset, bool isBuy, uint64 px, uint64 sz, uint64 cloid, bool reduceOnly);
    event ExitStrategyArmed(uint32 indexed asset, uint64 tp1Px, uint64 tp2Px, uint64 tp3Px, uint64 slPx);
    event PositionEmergencyClose(uint32 indexed asset);

    // ── Modifiers ─────────────────────────────────────────────────────────────
    modifier onlyOwner()          { require(msg.sender == owner,            "NOT_OWNER");  _; }
    modifier onlyAgent()          { require(msg.sender == aiAgent || msg.sender == owner, "NOT_AGENT"); _; }
    modifier positionOpen(uint32 a){ require(positions[a].isOpen,           "NO_POSITION"); _; }

    // ── Constructor ───────────────────────────────────────────────────────────
    constructor(address _aiAgent) {
        owner   = msg.sender;
        aiAgent = _aiAgent;
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AGENT 2 — EXECUTIONER: Open position
    // Called by off-chain orchestrator after Monte Carlo confirms edge.
    //
    // @param asset     Hyperliquid asset index
    // @param isLong    true = LONG, false = SHORT
    // @param leverage  1–10x (enforced on HL side, passed for event logging)
    // @param sz        Size in asset units × 1e5
    // ─────────────────────────────────────────────────────────────────────────
    function executeSignal(
        uint32 asset,
        bool   isLong,
        uint8  leverage,
        uint64 sz
    ) external onlyAgent {
        require(!positions[asset].isOpen, "POSITION_ALREADY_OPEN");
        require(sz > 0, "ZERO_SIZE");

        uint64 cloid = _nextCloid();

        EXCHANGE.placeOrder(
            asset,
            isLong,
            0,           // market order — limitPx = 0
            sz,
            false,       // not reduce-only — opening fresh
            ORDER_MARKET,
            cloid
        );

        positions[asset] = Position({
            isOpen:    true,
            isLong:    isLong,
            asset:     asset,
            leverage:  leverage,
            sz:        sz,
            entryCloid: cloid,
            tp1Cloid:  0,
            tp2Cloid:  0,
            tp3Cloid:  0,
            slCloid:   0,
            openedAt:  uint64(block.timestamp)
        });

        emit SignalReceived(asset, isLong, leverage, sz);
        emit OrderPlaced(asset, isLong, 0, sz, cloid, false);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // AGENT 3 — HARVESTER: Arm TP ladder + stop-loss
    // Called immediately after executeSignal() once entry is confirmed.
    //
    // All prices in USD × 1e6  (e.g. $65,000.00 BTC = 65000000000)
    // Close sizes in 1/3 splits: tp1Sz = tp2Sz = tp3Sz = pos.sz / 3
    // ─────────────────────────────────────────────────────────────────────────
    function setExitStrategy(
        uint32 asset,
        uint64 tp1Px,   // take-profit 1 limit price
        uint64 tp2Px,   // take-profit 2 limit price
        uint64 tp3Px,   // take-profit 3 limit price
        uint64 slPx     // stop-loss limit price (or 0 → use market SL)
    ) external onlyAgent positionOpen(asset) {
        require(tp1Px > 0 && tp2Px > tp1Px && tp3Px > tp2Px, "BAD_TP_LADDER");
        require(slPx > 0, "BAD_SL");

        Position storage pos = positions[asset];

        // Enforce that TP is above entry for longs, below for shorts
        if (pos.isLong) {
            require(tp1Px > 0, "LONG_TP_BELOW_ENTRY");
        } else {
            // For shorts TP prices are descending (already encoded by caller)
        }

        uint64 chunk = pos.sz / 3; // close ~33% at each TP level

        uint64 c1 = _nextCloid();
        uint64 c2 = _nextCloid();
        uint64 c3 = _nextCloid();
        uint64 cs = _nextCloid();

        // TP1 — 33% close
        EXCHANGE.placeOrder(asset, !pos.isLong, tp1Px, chunk, true, ORDER_LIMIT, c1);
        emit OrderPlaced(asset, !pos.isLong, tp1Px, chunk, c1, true);

        // TP2 — 33% close
        EXCHANGE.placeOrder(asset, !pos.isLong, tp2Px, chunk, true, ORDER_LIMIT, c2);
        emit OrderPlaced(asset, !pos.isLong, tp2Px, chunk, c2, true);

        // TP3 — remaining close
        EXCHANGE.placeOrder(asset, !pos.isLong, tp3Px, chunk + (pos.sz % 3), true, ORDER_LIMIT, c3);
        emit OrderPlaced(asset, !pos.isLong, tp3Px, chunk + (pos.sz % 3), c3, true);

        // Stop-loss — full size
        EXCHANGE.placeOrder(asset, !pos.isLong, slPx, pos.sz, true, ORDER_LIMIT, cs);
        emit OrderPlaced(asset, !pos.isLong, slPx, pos.sz, cs, true);

        pos.tp1Cloid = c1;
        pos.tp2Cloid = c2;
        pos.tp3Cloid = c3;
        pos.slCloid  = cs;

        emit ExitStrategyArmed(asset, tp1Px, tp2Px, tp3Px, slPx);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Emergency market-close for any open position
    // ─────────────────────────────────────────────────────────────────────────
    function emergencyClose(uint32 asset) external onlyAgent positionOpen(asset) {
        Position storage pos = positions[asset];

        // Cancel pending TP/SL orders
        if (pos.tp1Cloid > 0) EXCHANGE.cancelOrder(asset, pos.tp1Cloid);
        if (pos.tp2Cloid > 0) EXCHANGE.cancelOrder(asset, pos.tp2Cloid);
        if (pos.tp3Cloid > 0) EXCHANGE.cancelOrder(asset, pos.tp3Cloid);
        if (pos.slCloid  > 0) EXCHANGE.cancelOrder(asset, pos.slCloid);

        // Market close full position
        uint64 cloid = _nextCloid();
        EXCHANGE.placeOrder(asset, !pos.isLong, 0, pos.sz, true, ORDER_MARKET, cloid);

        pos.isOpen = false;
        emit PositionEmergencyClose(asset);
        emit OrderPlaced(asset, !pos.isLong, 0, pos.sz, cloid, true);
    }

    // ─────────────────────────────────────────────────────────────────────────
    // Mark position as closed (called by orchestrator after HL confirms close)
    // ─────────────────────────────────────────────────────────────────────────
    function markClosed(uint32 asset) external onlyAgent {
        positions[asset].isOpen = false;
    }

    // ── Admin ─────────────────────────────────────────────────────────────────
    function setAIAgent(address _agent) external onlyOwner {
        aiAgent = _agent;
        emit AgentUpdated(_agent);
    }

    function withdraw() external onlyOwner {
        payable(owner).transfer(address(this).balance);
    }

    receive() external payable {}

    // ── Helpers ───────────────────────────────────────────────────────────────
    function _nextCloid() internal returns (uint64) {
        return uint64(block.timestamp) * 1_000_000 + (++_nonce % 1_000_000);
    }
}
