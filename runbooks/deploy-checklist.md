# TokenChain Deploy Checklist

## Pre-deploy
- Verify `main` branch is green in `tokenchain-chain`.
- Build binaries: `tokenchaind`, `tokenchain-indexer`, `tokenchain-faucet`.
- Confirm DNS records resolve to VPS.
- Confirm all 16 `tokenchain` + `testnet.tokenchain` hostnames resolve.

## Deploy sequence
1. Deploy chain binary and install `libwasmvm.x86_64.so` in `/usr/local/lib` if needed.
2. Initialize `/var/lib/tokenchain-testnet` if first boot and patch wasm upload policy.
3. Deploy indexer binary and web build artifacts.
4. Deploy faucet binary (`tokenchain-faucet`).
5. Restart:
   - `tokenchaind-testnet`
   - `tokenchain-indexer`
   - `tokenchain-web`
   - `tokenchain-faucet`
6. Reload nginx with `nginx/tokenchain-unified.conf`.
7. Issue/renew cert with `certbot certonly --webroot` for all hostnames.
8. Verify health checks:
   - `GET /healthz` on API host
   - `GET /healthz` on faucet host
   - RPC status endpoint
   - REST node info endpoint
9. Verify relayer service status.

## Post-deploy validation
- Confirm explorer connectivity.
- Confirm wallet can query balances.
- Confirm API returns chain metadata.
- Confirm `seed.*` resolves and `26656/tcp` is reachable.
