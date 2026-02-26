# TokenChain Deploy Checklist

## Pre-deploy
- Verify `main` branch is green in `tokenchain-chain`.
- Build binaries: `tokenchaind`, `tokenchain-indexer`.
- Confirm DNS records resolve to VPS.
- Confirm `grpc.*` DNS is DNS-only and not HTTP proxied.

## Deploy sequence
1. Deploy chain binary and restart `tokenchaind`.
2. Deploy indexer binary and restart `tokenchain-indexer`.
3. Reload nginx with updated vhosts.
4. Verify health checks:
   - `GET /healthz` on API host
   - RPC status endpoint
   - REST node info endpoint
5. Verify relayer service status.

## Post-deploy validation
- Confirm explorer connectivity.
- Confirm wallet can query balances.
- Confirm API returns chain metadata.
