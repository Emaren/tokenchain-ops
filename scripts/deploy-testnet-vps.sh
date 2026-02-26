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

echo "[4/8] Building web app"
cd "${WEB_REPO}"
runuser -u tony -- npm ci
runuser -u tony -- npm run build

echo "[5/8] Installing service + nginx templates"
cp "${OPS_REPO}/systemd/tokenchaind-testnet.service" /etc/systemd/system/tokenchaind-testnet.service
cp "${OPS_REPO}/systemd/tokenchain-indexer.service" /etc/systemd/system/tokenchain-indexer.service
cp "${OPS_REPO}/systemd/tokenchain-faucet.service" /etc/systemd/system/tokenchain-faucet.service
cp "${OPS_REPO}/systemd/tokenchain-web.service" /etc/systemd/system/tokenchain-web.service
cp "${OPS_REPO}/nginx/tokenchain-unified.conf" /etc/nginx/sites-available/tokenchain.tokentap.ca
ln -sf /etc/nginx/sites-available/tokenchain.tokentap.ca /etc/nginx/sites-enabled/tokenchain.tokentap.ca

echo "[6/8] Writing tokenchaind runtime env"
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

echo "[7/8] Reloading systemd + restarting services"
systemctl daemon-reload
systemctl enable --now tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web
systemctl restart tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web

echo "[8/8] Reloading nginx"
nginx -t
systemctl reload nginx

echo "[9/9] Health summary"
echo "- Services:"
systemctl is-active tokenchaind-testnet tokenchain-indexer tokenchain-faucet tokenchain-web nginx
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
