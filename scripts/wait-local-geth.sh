#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${LOCAL_GETH_RPC_URL:-http://127.0.0.1:8545}"
SUBSTREAMS_ENDPOINT="${SUBSTREAMS_ENDPOINT:-localhost:9000}"
SUBSTREAMS_BIN="${SUBSTREAMS_BIN:-$(command -v substreams-v1.17 || command -v substreams)}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-120}"

deadline=$((SECONDS + TIMEOUT_SECONDS))
until cast chain-id --rpc-url "${RPC_URL}" >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Geth RPC at ${RPC_URL}" >&2
    exit 1
  fi
  sleep 1
done

chain_id="$(cast chain-id --rpc-url "${RPC_URL}")"
echo "Local Geth RPC ready at ${RPC_URL} (chain id ${chain_id})"

deadline=$((SECONDS + TIMEOUT_SECONDS))
until start_block="$(cast block-number --rpc-url "${RPC_URL}")" \
  && "${SUBSTREAMS_BIN}" run -e "${SUBSTREAMS_ENDPOINT}" --plaintext common@v0.1.0 -o clock -s "${start_block}" -t +1 >/dev/null 2>&1; do
  if (( SECONDS >= deadline )); then
    echo "Timed out waiting for Substreams endpoint at ${SUBSTREAMS_ENDPOINT}" >&2
    exit 1
  fi
  sleep 1
done

echo "Substreams endpoint ready at ${SUBSTREAMS_ENDPOINT}"
