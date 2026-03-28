[profile.default]
src     = "src"
out     = "out"
libs    = ["lib"]
test    = "test"
script  = "script"
solc    = "0.8.20"
optimizer       = true
optimizer_runs  = 200

[rpc_endpoints]
hyperevm = "https://rpc.hyperliquid.xyz/evm"

[etherscan]
# HyperEVM non ha ancora Etherscan ufficiale
# hyperevm = { key = "${ETHERSCAN_API_KEY}", url = "..." }
