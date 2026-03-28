// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/OpenClawAgent.sol";

/// @notice Script di deploy per OpenClawAgent su HyperEVM.
///
/// Uso:
///   forge script script/DeployOpenClaw.s.sol \
///     --rpc-url https://rpc.hyperliquid.xyz/evm \
///     --private-key $OPENCLAW_PRIVATE_KEY \
///     --broadcast -v
///
/// Dopo il deploy, copia l'indirizzo del contratto in .env:
///   OPENCLAW_CONTRACT=0x...
contract DeployOpenClaw is Script {

    function run() external {
        // Il wallet che esegue lo script diventa l'owner del contratto.
        // Il parametro del costruttore è l'indirizzo dell'agente AI autorizzato
        // a chiamare executeSignal() e setExitStrategy().
        // Puoi usare lo stesso wallet o uno separato.
        address aiAgent = vm.envOr(
            "OPENCLAW_AGENT_ADDRESS",
            vm.addr(vm.envUint("OPENCLAW_PRIVATE_KEY"))
        );

        console.log("Deploying OpenClawAgent...");
        console.log("Owner (deployer):", msg.sender);
        console.log("AI Agent address:", aiAgent);

        vm.startBroadcast();
        OpenClawAgent agent = new OpenClawAgent(aiAgent);
        vm.stopBroadcast();

        console.log("OpenClawAgent deployed at:", address(agent));
        console.log("");
        console.log("Aggiungi al tuo .env:");
        console.log("OPENCLAW_CONTRACT=", address(agent));
    }
}
