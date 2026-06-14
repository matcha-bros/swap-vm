#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RPC_URL="${LOCAL_GETH_RPC_URL:-http://127.0.0.1:8545}"
PRIVATE_KEY="${LOCALHOST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

cd "${ROOT_DIR}"

docker compose -f docker-compose.firehose-geth.yaml up -d
LOCAL_GETH_RPC_URL="${RPC_URL}" scripts/wait-local-geth.sh

LOCALHOST_RPC_URL="${RPC_URL}" scripts/ensure-create2-deployer.sh

start_block="$(cast block-number --rpc-url "${RPC_URL}")"
echo "Deploying local Aqua SwapVM contracts to Local Geth from block ${start_block}"
forge script script/local/DeployLocal.s.sol:DeployLocalScript \
  --rpc-url "${RPC_URL}" \
  --private-key "${PRIVATE_KEY}" \
  --broadcast

echo "Local Geth deployment start block: ${start_block}"
echo "Local deployment artifact:"
echo "  ${ROOT_DIR}/deployments/local.json"
echo
echo "Pack/test Tycho Aqua SwapVM with:"
echo "  cd ../tycho && AQUA_START_BLOCK=${start_block} protocols/substreams/ethereum-aqua-swapvm/scripts/pack-local.sh"
