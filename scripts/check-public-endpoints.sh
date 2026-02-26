#!/usr/bin/env bash
set -euo pipefail

EXPECTED_IP="${EXPECTED_IP:-157.180.114.124}"
NETWORK="${NETWORK:-testnet}"

if [[ "${NETWORK}" == "mainnet" ]]; then
  WEB_HOST="tokenchain.tokentap.ca"
  API_HOST="api.tokenchain.tokentap.ca"
  RPC_HOST="rpc.tokenchain.tokentap.ca"
  REST_HOST="rest.tokenchain.tokentap.ca"
  FAUCET_HOST="faucet.tokenchain.tokentap.ca"
  EXPLORER_HOST="explorer.tokenchain.tokentap.ca"
  GRPC_HOST="grpc.tokenchain.tokentap.ca"
  SEED_HOST="seed.tokenchain.tokentap.ca"
else
  WEB_HOST="testnet.tokenchain.tokentap.ca"
  API_HOST="api.testnet.tokenchain.tokentap.ca"
  RPC_HOST="rpc.testnet.tokenchain.tokentap.ca"
  REST_HOST="rest.testnet.tokenchain.tokentap.ca"
  FAUCET_HOST="faucet.testnet.tokenchain.tokentap.ca"
  EXPLORER_HOST="explorer.testnet.tokenchain.tokentap.ca"
  GRPC_HOST="grpc.testnet.tokenchain.tokentap.ca"
  SEED_HOST="seed.testnet.tokenchain.tokentap.ca"
fi

hosts=(
  "${WEB_HOST}"
  "${API_HOST}"
  "${RPC_HOST}"
  "${REST_HOST}"
  "${FAUCET_HOST}"
  "${EXPLORER_HOST}"
  "${GRPC_HOST}"
  "${SEED_HOST}"
)

for bin in curl jq dig; do
  if ! command -v "${bin}" >/dev/null 2>&1; then
    echo "ERROR: missing required binary: ${bin}" >&2
    exit 1
  fi
done

check_host_dns() {
  local host="$1"
  local got
  got="$(dig +short "${host}" | head -n1)"
  if [[ -z "${got}" ]]; then
    echo "FAIL dns ${host}: no A record"
    return 1
  fi
  if [[ "${EXPECTED_IP}" != "" && "${got}" != "${EXPECTED_IP}" ]]; then
    echo "FAIL dns ${host}: ${got} (expected ${EXPECTED_IP})"
    return 1
  fi
  echo "PASS dns ${host}: ${got}"
}

check_https_code() {
  local host="$1"
  local code
  code="$(curl -sS -o /dev/null -w '%{http_code}' "https://${host}")"
  case "${code}" in
    200|302|404|415)
      echo "PASS https ${host}: ${code}"
      ;;
    *)
      echo "FAIL https ${host}: ${code}"
      return 1
      ;;
  esac
}

check_json_ok() {
  local label="$1"
  local url="$2"
  if curl -fsS "${url}" | jq . >/dev/null; then
    echo "PASS ${label}"
  else
    echo "FAIL ${label}: ${url}"
    return 1
  fi
}

echo "== TokenChain public endpoint check (${NETWORK}) =="
echo

for host in "${hosts[@]}"; do
  check_host_dns "${host}"
done

echo
for host in "${hosts[@]}"; do
  check_https_code "${host}"
done

echo
check_json_ok "api /healthz" "https://${API_HOST}/healthz"
check_json_ok "faucet /healthz" "https://${FAUCET_HOST}/healthz"
check_json_ok "rpc /status" "https://${RPC_HOST}/status"
check_json_ok "rest /node_info" "https://${REST_HOST}/cosmos/base/tendermint/v1beta1/node_info"
check_json_ok "ibc relayer status" "https://${API_HOST}/v1/ibc/relayer-status"
check_json_ok "ibc channels" "https://${API_HOST}/v1/ibc/channels?port_id=transfer"

RPC_CHAIN_ID="$(curl -fsS "https://${RPC_HOST}/status" | jq -r '.result.node_info.network')"
REST_CHAIN_ID="$(curl -fsS "https://${REST_HOST}/cosmos/base/tendermint/v1beta1/node_info" | jq -r '.default_node_info.network')"

if [[ -z "${RPC_CHAIN_ID}" || "${RPC_CHAIN_ID}" == "null" ]]; then
  echo "FAIL rpc chain id: empty"
  exit 1
fi
if [[ "${RPC_CHAIN_ID}" != "${REST_CHAIN_ID}" ]]; then
  echo "FAIL chain id mismatch: rpc=${RPC_CHAIN_ID} rest=${REST_CHAIN_ID}"
  exit 1
fi

HEIGHT="$(curl -fsS "https://${RPC_HOST}/status" | jq -r '.result.sync_info.latest_block_height')"
RELAYER_ACTIVE="$(curl -fsS "https://${API_HOST}/v1/ibc/relayer-status" | jq -r '.service_active')"

echo
echo "PASS chain id: ${RPC_CHAIN_ID}"
echo "PASS latest height: ${HEIGHT}"
echo "PASS relayer service: ${RELAYER_ACTIVE}"
echo
echo "All checks passed."
