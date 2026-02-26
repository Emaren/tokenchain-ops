# tokenchain-ops

Operational configs and runbooks for TokenChain.

## Contents
- `nginx/` reverse-proxy vhosts for web, API, RPC, REST, and explorer
- `systemd/` service units for chain, indexer, relayer
- `relayer/` Hermes configuration templates
- `runbooks/` deployment and incident response notes
- `scripts/` helper scripts for sync/deploy

## Fast deploy (VPS)
On the VPS as root:
```bash
/var/www/tokenchain-ops/scripts/deploy-testnet-vps.sh
```

Optional deploy env knobs:
- `MIN_AVAILABLE_KB` minimum free space required before web build (default `1572864`, ~1.5GB)

The deploy script writes `/etc/tokenchain/tokenchaind-testnet.env` with:
- `TOKENCHAIN_LOYALTY_AUTHORITY=<founder-address>`
- and bootstraps `/etc/tokenchain/tokenchain-indexer.env` (admin API settings; disabled until `ADMIN_API_TOKEN` is set)

To enable indexer admin tx endpoint:
1. Edit `/etc/tokenchain/tokenchain-indexer.env`
2. Set `ADMIN_API_TOKEN=<strong-random-secret>`
3. `systemctl restart tokenchain-indexer`

This enables founder-operated day-1 loyalty admin flows while keeping the chain default (`x/gov`) when unset.

Daily merchant allocation automation:
1. Edit `/etc/tokenchain/tokenchain-daily-allocation.env`
2. Set:
   - `ADMIN_API_TOKEN=<same indexer admin token>`
   - `TOTAL_BUCKET_C_AMOUNT=<daily utoken amount for Bucket C>`
   - `ALLOCATION_MODE=auto` (recommended) or `manual`
   - Auto mode:
     - `MIN_ACTIVITY_SCORE=1`
     - `MAX_AUTO_TOKENS=200`
   - Manual mode:
     - `ALLOCATION_ITEMS_JSON='[{"denom":"factory/...","activity_score":123}]'`
3. Set `DRY_RUN=false` once ready.
4. Start/check timer:
   - `systemctl enable --now tokenchain-daily-allocation.timer`
   - `systemctl list-timers tokenchain-daily-allocation.timer`

The timer runs daily at midnight `America/Edmonton` and calls:
- `POST /v1/admin/loyalty/daily-allocation/run`

Relayer setup guide:
- `runbooks/relayer-bootstrap.md`

## DNS model
Mainnet hostnames (recommended):
- `tokenchain.tokentap.ca`
- `api.tokenchain.tokentap.ca`
- `rpc.tokenchain.tokentap.ca`
- `rest.tokenchain.tokentap.ca`
- `grpc.tokenchain.tokentap.ca` (gRPC over TLS via nginx)
- `explorer.tokenchain.tokentap.ca`
- `seed.tokenchain.tokentap.ca`
- `faucet.tokenchain.tokentap.ca`

Testnet equivalents:
- `testnet.tokenchain.tokentap.ca`
- `api.testnet.tokenchain.tokentap.ca`
- `rpc.testnet.tokenchain.tokentap.ca`
- `rest.testnet.tokenchain.tokentap.ca`
- `grpc.testnet.tokenchain.tokentap.ca`
- `explorer.testnet.tokenchain.tokentap.ca`
- `seed.testnet.tokenchain.tokentap.ca`
- `faucet.testnet.tokenchain.tokentap.ca`

## Current VPS bootstrap layout
- Chain service: `tokenchaind-testnet.service`
- Chain home: `/var/lib/tokenchain-testnet`
- Chain binary: `/usr/local/bin/tokenchaind`
- Web service: `tokenchain-web.service` (`127.0.0.1:3021`)
- API service: `tokenchain-indexer.service` (`127.0.0.1:3321`)
  - uses local RPC `127.0.0.1:26657` and local REST `127.0.0.1:1317`
- Faucet service: `tokenchain-faucet.service` (`127.0.0.1:3322`)
- Nginx vhost: `nginx/tokenchain-unified.conf` (single file for all 16 hostnames)

This bootstrap maps both `*.tokenchain.tokentap.ca` and `*.testnet.tokenchain.tokentap.ca`
to the same testnet backend until mainnet is launched.
