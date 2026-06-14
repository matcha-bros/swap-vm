#!/usr/bin/env bash
set -euo pipefail

RPC_URL="${LOCALHOST_RPC_URL:-${LOCAL_GETH_RPC_URL:-http://127.0.0.1:8545}}"
PRIVATE_KEY="${LOCALHOST_PRIVATE_KEY:-0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80}"

DETERMINISTIC_DEPLOYER="0x4e59b44847b379578588920cA78FbF26c0B4956C"
FOUNDRY_DEPLOYER="0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
DEPLOYER_SIGNER="0x3fAB184622Dc19b6109349B94811493BF2a45362"
EXPECTED_RUNTIME="0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf3"
RAW_CREATE2_TX="0xf8a58085174876e800830186a08080b853604580600e600039806000f350fe7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffe03601600081602082378035828234f58015156039578182fd5b8082525050506014600cf31ba02222222222222222222222222222222222222222222222222222222222222222a02222222222222222222222222222222222222222222222222222222222222222"
LOCAL_ACCOUNT_FUND_ETHER="${LOCAL_ACCOUNT_FUND_ETHER:-10000}"
FUND_VALUE_WEI="$(cast to-wei "${LOCAL_ACCOUNT_FUND_ETHER}" ether)"
FUND_VALUE_HEX="$(cast to-hex "${FUND_VALUE_WEI}")"

fund_from_dev_account() {
  local recipient="$1"
  local balance
  balance="$(cast balance "${recipient}" --rpc-url "${RPC_URL}")"
  if [[ "${balance}" != "0" ]]; then
    echo "${recipient} already funded with ${balance} wei"
    return
  fi

  local funder
  funder="$(cast rpc eth_accounts --rpc-url "${RPC_URL}" | jq -r '.[0]')"
  if [[ ! "${funder}" =~ ^0x[0-9a-fA-F]{40}$ ]]; then
    echo "Unable to discover unlocked Geth dev account" >&2
    exit 1
  fi

  echo "Funding ${recipient} from unlocked Geth dev account ${funder}"
  cast rpc eth_sendTransaction "{\"from\":\"${funder}\",\"to\":\"${recipient}\",\"value\":\"${FUND_VALUE_HEX}\"}" --rpc-url "${RPC_URL}" >/dev/null

  for _ in {1..30}; do
    balance="$(cast balance "${recipient}" --rpc-url "${RPC_URL}")"
    if [[ "${balance}" != "0" ]]; then
      echo "${recipient} funded with ${balance} wei"
      return
    fi
    sleep 1
  done

  echo "Timed out waiting for ${recipient} funding transaction to mine" >&2
  exit 1
}

fund_from_dev_account "${FOUNDRY_DEPLOYER}"
fund_from_dev_account "${DEPLOYER_SIGNER}"

current_code="$(cast code "${DETERMINISTIC_DEPLOYER}" --rpc-url "${RPC_URL}")"
if [[ "${current_code,,}" == "${EXPECTED_RUNTIME,,}" ]]; then
  echo "CREATE2 deployer already installed at ${DETERMINISTIC_DEPLOYER}"
  exit 0
fi

echo "Broadcasting canonical CREATE2 deployer transaction"
cast publish "${RAW_CREATE2_TX}" --rpc-url "${RPC_URL}" >/dev/null

current_code="$(cast code "${DETERMINISTIC_DEPLOYER}" --rpc-url "${RPC_URL}")"
if [[ "${current_code,,}" != "${EXPECTED_RUNTIME,,}" ]]; then
  echo "CREATE2 deployer bytecode mismatch at ${DETERMINISTIC_DEPLOYER}" >&2
  echo "Expected: ${EXPECTED_RUNTIME}" >&2
  echo "Actual:   ${current_code}" >&2
  exit 1
fi

echo "CREATE2 deployer installed at ${DETERMINISTIC_DEPLOYER}"
