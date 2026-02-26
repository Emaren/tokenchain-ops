#!/usr/bin/env bash
set -euo pipefail

A_CHAIN="${A_CHAIN:-tokenchain-testnet-1}"
B_CHAIN="${B_CHAIN:-osmo-test-5}"

TOKENCHAIN_REST="${TOKENCHAIN_REST:-https://rest.testnet.tokenchain.tokentap.ca}"
OSMO_REST="${OSMO_REST:-https://lcd.osmotest5.osmosis.zone}"

HERMES_BIN="${HERMES_BIN:-/usr/local/bin/hermes}"
HERMES_CONFIG="${HERMES_CONFIG:-/etc/tokenchain/hermes.toml}"

A_PORT="${A_PORT:-transfer}"
B_PORT="${B_PORT:-transfer}"
CHANNEL_VERSION="${CHANNEL_VERSION:-ics20-1}"

for bin in curl jq runuser; do
  if ! command -v "$bin" >/dev/null 2>&1; then
    echo "ERROR: missing required binary: $bin" >&2
    exit 1
  fi
done

if [[ ! -x "${HERMES_BIN}" ]]; then
  echo "ERROR: Hermes binary not found/executable at ${HERMES_BIN}" >&2
  exit 1
fi

if [[ ! -f "${HERMES_CONFIG}" ]]; then
  echo "ERROR: Hermes config not found at ${HERMES_CONFIG}" >&2
  exit 1
fi

run_hermes() {
  runuser -u tokenchain -- "${HERMES_BIN}" --config "${HERMES_CONFIG}" "$@"
}

get_client_id() {
  local rest="$1"
  local remote_chain="$2"
  curl -fsS "${rest}/ibc/core/client/v1/client_states?pagination.limit=500" \
    | jq -r --arg remote "${remote_chain}" '.client_states[]? | select(.client_state.chain_id == $remote) | .client_id' \
    | head -n1
}

get_open_connection_id() {
  local rest="$1"
  local client_id="$2"
  curl -fsS "${rest}/ibc/core/connection/v1/connections?pagination.limit=500" \
    | jq -r --arg client "${client_id}" '.connections[]? | select(.client_id == $client and .state == "STATE_OPEN") | .id' \
    | head -n1
}

get_open_channel_id() {
  local rest="$1"
  local port="$2"
  local connection_id="$3"
  curl -fsS "${rest}/ibc/core/channel/v1/channels?pagination.limit=500" \
    | jq -r --arg port "${port}" --arg conn "${connection_id}" '.channels[]? | select(.port_id == $port and .state == "STATE_OPEN" and (.connection_hops[0] // "") == $conn) | .channel_id' \
    | head -n1
}

osmosis_relayer_address() {
  run_hermes keys list --chain "${B_CHAIN}" 2>/dev/null | sed -n -E 's/.*\((osmo1[[:alnum:]]+)\).*/\1/p' | head -n1
}

echo "[1/6] Hermes health-check"
run_hermes health-check >/dev/null

echo "[2/6] Ensure client ${A_CHAIN} -> ${B_CHAIN}"
A_CLIENT="$(get_client_id "${TOKENCHAIN_REST}" "${B_CHAIN}")"
if [[ -z "${A_CLIENT}" ]]; then
  run_hermes create client --host-chain "${A_CHAIN}" --reference-chain "${B_CHAIN}" >/dev/null
  A_CLIENT="$(get_client_id "${TOKENCHAIN_REST}" "${B_CHAIN}")"
fi
if [[ -z "${A_CLIENT}" ]]; then
  echo "ERROR: could not find/create ${A_CHAIN} client for ${B_CHAIN}" >&2
  exit 1
fi
echo "  client: ${A_CLIENT}"

echo "[3/6] Ensure client ${B_CHAIN} -> ${A_CHAIN}"
B_CLIENT="$(get_client_id "${OSMO_REST}" "${A_CHAIN}")"
if [[ -z "${B_CLIENT}" ]]; then
  set +e
  CLIENT_ERR="$(run_hermes create client --host-chain "${B_CHAIN}" --reference-chain "${A_CHAIN}" 2>&1)"
  CLIENT_CODE=$?
  set -e
  if [[ ${CLIENT_CODE} -ne 0 ]]; then
    if echo "${CLIENT_ERR}" | rg -q 'account .* not found'; then
      OSMO_ADDR="$(osmosis_relayer_address)"
      echo "ERROR: osmo relayer key is not funded yet." >&2
      if [[ -n "${OSMO_ADDR}" ]]; then
        echo "Fund this address on Osmosis testnet faucet and rerun:" >&2
        echo "  ${OSMO_ADDR}" >&2
        echo "Faucet: https://faucet.testnet.osmosis.zone" >&2
      fi
      exit 2
    fi
    echo "${CLIENT_ERR}" >&2
    exit ${CLIENT_CODE}
  fi
  B_CLIENT="$(get_client_id "${OSMO_REST}" "${A_CHAIN}")"
fi
if [[ -z "${B_CLIENT}" ]]; then
  echo "ERROR: could not find/create ${B_CHAIN} client for ${A_CHAIN}" >&2
  exit 1
fi
echo "  client: ${B_CLIENT}"

echo "[4/6] Ensure open connection"
A_CONNECTION="$(get_open_connection_id "${TOKENCHAIN_REST}" "${A_CLIENT}")"
if [[ -z "${A_CONNECTION}" ]]; then
  run_hermes create connection --a-chain "${A_CHAIN}" --a-client "${A_CLIENT}" --b-client "${B_CLIENT}" >/dev/null
  A_CONNECTION="$(get_open_connection_id "${TOKENCHAIN_REST}" "${A_CLIENT}")"
fi
if [[ -z "${A_CONNECTION}" ]]; then
  echo "ERROR: could not find/create open connection on ${A_CHAIN}" >&2
  exit 1
fi
echo "  connection: ${A_CONNECTION}"

echo "[5/6] Ensure transfer channel"
A_CHANNEL="$(get_open_channel_id "${TOKENCHAIN_REST}" "${A_PORT}" "${A_CONNECTION}")"
if [[ -z "${A_CHANNEL}" ]]; then
  run_hermes create channel \
    --a-chain "${A_CHAIN}" \
    --a-connection "${A_CONNECTION}" \
    --a-port "${A_PORT}" \
    --b-port "${B_PORT}" \
    --channel-version "${CHANNEL_VERSION}" >/dev/null
  A_CHANNEL="$(get_open_channel_id "${TOKENCHAIN_REST}" "${A_PORT}" "${A_CONNECTION}")"
fi
if [[ -z "${A_CHANNEL}" ]]; then
  echo "ERROR: could not find/create transfer channel on ${A_CHAIN}" >&2
  exit 1
fi
echo "  channel: ${A_CHANNEL}"

echo "[6/6] Done"
echo "TokenChain channel: ${A_PORT}/${A_CHANNEL}"
echo "Check: ${TOKENCHAIN_REST}/ibc/core/channel/v1/channels?pagination.limit=50"
