#!/usr/bin/env bash
set -euo pipefail

# Run this script on the VPS as root.

GO_TOOLCHAIN="${GO_TOOLCHAIN:-go1.24.10}"
CHAIN_REPO="${CHAIN_REPO:-/var/www/tokenchain-chain}"
INDEXER_REPO="${INDEXER_REPO:-/var/www/tokenchain-indexer}"
WEB_REPO="${WEB_REPO:-/var/www/tokenchain-web}"
OPS_REPO="${OPS_REPO:-/var/www/tokenchain-ops}"
CHAIN_HOME="${CHAIN_HOME:-/var/lib/tokenchain-testnet}"
CHAIN_ENV_FILE="${CHAIN_ENV_FILE:-/etc/tokenchain/tokenchaind-testnet.env}"
INDEXER_ENV_FILE="${INDEXER_ENV_FILE:-/etc/tokenchain/tokenchain-indexer.env}"
DAILY_ALLOCATION_ENV_FILE="${DAILY_ALLOCATION_ENV_FILE:-/etc/tokenchain/tokenchain-daily-allocation.env}"
MIN_AVAILABLE_KB="${MIN_AVAILABLE_KB:-1572864}" # 1.5 GB
ENABLE_OSMO_IBC_TIMER="${ENABLE_OSMO_IBC_TIMER:-false}"

disk_available_kb() {
  df -Pk / | awk 'NR==2 {print $4}'
}

print_disk_summary() {
  echo "Filesystem usage:"
  df -h / /var /home
  echo "Largest /var/www directories:"
  du -h -d1 /var/www 2>/dev/null | sort -h | tail -n 15
}

cleanup_web_build_artifacts() {
  rm -rf "${WEB_REPO}/node_modules" "${WEB_REPO}/.next"
  runuser -u tony -- npm cache clean --force >/dev/null 2>&1 || true
  rm -rf /home/tony/.npm/_logs/* 2>/dev/null || true
}

ensure_disk_headroom() {
  local available_kb
  available_kb="$(disk_available_kb)"
  if (( available_kb >= MIN_AVAILABLE_KB )); then
    return
  fi

  echo "WARN: low disk before web build (${available_kb} KB available; need ${MIN_AVAILABLE_KB} KB)."
  echo "Cleaning rebuildable web/npm artifacts..."
  cleanup_web_build_artifacts

  available_kb="$(disk_available_kb)"
  if (( available_kb < MIN_AVAILABLE_KB )); then
    echo "ERROR: insufficient disk after cleanup (${available_kb} KB available; need ${MIN_AVAILABLE_KB} KB)."
    print_disk_summary
    exit 1
  fi
}

echo "[1/8] Pulling latest repos"
runuser -u tony -- git -C "${CHAIN_REPO}" pull --ff-only
runuser -u tony -- git -C "${INDEXER_REPO}" pull --ff-only
runuser -u tony -- git -C "${WEB_REPO}" pull --ff-only
runuser -u tony -- git -C "${OPS_REPO}" pull --ff-only

echo "[2/8] Building chain + indexer + faucet binaries"
export GOTOOLCHAIN="${GO_TOOLCHAIN}"
cd "${CHAIN_REPO}"
go build -buildvcs=false -o /usr/local/bin/tokenchaind ./cmd/tokenchaind
cd "${INDEXER_REPO}"
go build -buildvcs=false -o /usr/local/bin/tokenchain-indexer ./cmd/tokenchain-indexer
go build -buildvcs=false -o /usr/local/bin/tokenchain-faucet ./cmd/tokenchain-faucet

echo "[3/8] Ensuring wasm runtime library is installed"
if ! ldconfig -p | grep -q "libwasmvm.x86_64.so"; then
  WASM_LIB="$(find /root/go/pkg/mod -type f -name 'libwasmvm.x86_64.so' | head -n 1 || true)"
  if [[ -z "${WASM_LIB}" ]]; then
    echo "ERROR: libwasmvm.x86_64.so not found in Go module cache"
    exit 1
  fi
  cp "${WASM_LIB}" /usr/local/lib/libwasmvm.x86_64.so
  chmod 644 /usr/local/lib/libwasmvm.x86_64.so
  ldconfig
fi

echo "[4/10] Ensuring disk headroom for web build"
ensure_disk_headroom

echo "[5/10] Building web app"
cd "${WEB_REPO}"
runuser -u tony -- npm ci
runuser -u tony -- npm run build

echo "[6/10] Installing service + nginx templates"
cp "${OPS_REPO}/systemd/tokenchaind-testnet.service" /etc/systemd/system/tokenchaind-testnet.service
cp "${OPS_REPO}/systemd/tokenchain-indexer.service" /etc/systemd/system/tokenchain-indexer.service
cp "${OPS_REPO}/systemd/tokenchain-faucet.service" /etc/systemd/system/tokenchain-faucet.service
cp "${OPS_REPO}/systemd/tokenchain-web.service" /etc/systemd/system/tokenchain-web.service
cp "${OPS_REPO}/systemd/tokenchain-daily-allocation.service" /etc/systemd/system/tokenchain-daily-allocation.service
cp "${OPS_REPO}/systemd/tokenchain-daily-allocation.timer" /etc/systemd/system/tokenchain-daily-allocation.timer
cp "${OPS_REPO}/systemd/tokenchain-osmo-ibc-bootstrap.service" /etc/systemd/system/tokenchain-osmo-ibc-bootstrap.service
cp "${OPS_REPO}/systemd/tokenchain-osmo-ibc-bootstrap.timer" /etc/systemd/system/tokenchain-osmo-ibc-bootstrap.timer
cp "${OPS_REPO}/nginx/tokenchain-unified.conf" /etc/nginx/sites-available/tokenchain.tokentap.ca
ln -sf /etc/nginx/sites-available/tokenchain.tokentap.ca /etc/nginx/sites-enabled/tokenchain.tokentap.ca

echo "[7/10] Writing runtime env files"
install -d -m 755 /etc/tokenchain
FOUNDER_ADDR="$(runuser -u tokenchain -- tokenchaind keys show founder -a --keyring-backend test --home "${CHAIN_HOME}" 2>/dev/null || true)"
if [[ -n "${FOUNDER_ADDR}" ]]; then
  printf 'TOKENCHAIN_LOYALTY_AUTHORITY=%s\n' "${FOUNDER_ADDR}" >"${CHAIN_ENV_FILE}"
  chown root:tokenchain "${CHAIN_ENV_FILE}"
  chmod 640 "${CHAIN_ENV_FILE}"
  echo "  loyalty authority set to founder ${FOUNDER_ADDR}"
else
  echo "  WARN: founder key not found; leaving ${CHAIN_ENV_FILE} unchanged"
fi

if [[ ! -f "${INDEXER_ENV_FILE}" ]]; then
  cat >"${INDEXER_ENV_FILE}" <<EOF
ADMIN_API_TOKEN=
ADMIN_FROM_KEY=founder
CHAIN_HOME=${CHAIN_HOME}
KEYRING_BACKEND=test
TX_FEES=5000utoken
TX_GAS=200000
TOKENCHAIND_BIN=/usr/local/bin/tokenchaind
EOF
  chown root:tokenchain "${INDEXER_ENV_FILE}"
  chmod 640 "${INDEXER_ENV_FILE}"
  echo "  created ${INDEXER_ENV_FILE} (ADMIN_API_TOKEN empty; admin endpoint disabled)"
else
  echo "  preserving existing ${INDEXER_ENV_FILE}"
fi

if [[ ! -f "${DAILY_ALLOCATION_ENV_FILE}" ]]; then
  cat >"${DAILY_ALLOCATION_ENV_FILE}" <<EOF
API_BASE=http://127.0.0.1:3321
ADMIN_API_TOKEN=
TOTAL_BUCKET_C_AMOUNT=1000000
ALLOCATION_MODE=auto
MIN_ACTIVITY_SCORE=1
MAX_AUTO_TOKENS=200
ALLOCATION_ITEMS_JSON=[]
ALLOW_OVERWRITE=false
DRY_RUN=true
EOF
  chown root:tokenchain "${DAILY_ALLOCATION_ENV_FILE}"
  chmod 640 "${DAILY_ALLOCATION_ENV_FILE}"
  echo "  created ${DAILY_ALLOCATION_ENV_FILE} (configure token + items; DRY_RUN defaults to true)"
else
  echo "  preserving existing ${DAILY_ALLOCATION_ENV_FILE}"
fi

echo "[8/10] Reloading systemd + restarting services"
systemctl daemon-reload
systemctl enable --now tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web
systemctl restart tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web
systemctl enable --now tokenchain-daily-allocation.timer
if [[ "${ENABLE_OSMO_IBC_TIMER}" == "true" ]]; then
  systemctl enable --now tokenchain-osmo-ibc-bootstrap.timer
else
  echo "  osmo IBC bootstrap timer left disabled (set ENABLE_OSMO_IBC_TIMER=true to enable)"
fi

echo "[9/10] Reloading nginx"
nginx -t
systemctl reload nginx

echo "[10/10] Health summary"
echo "- Services:"
systemctl is-active tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web nginx
echo "- Timer:"
systemctl is-active tokenchain-daily-allocation.timer
echo "- API health:"
curl -fsS http://127.0.0.1:3321/healthz
echo
echo "- Faucet health:"
curl -fsS http://127.0.0.1:3322/healthz
echo
echo "- RPC status:"
for _ in {1..15}; do
  if curl -fsS http://127.0.0.1:26657/status >/tmp/tokenchain-rpc-status.json 2>/dev/null; then
    jq -r '.result.node_info.network + " height=" + .result.sync_info.latest_block_height' /tmp/tokenchain-rpc-status.json
    exit 0
  fi
  sleep 2
done
echo "ERROR: RPC did not become ready in time"
exit 1
