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

This enables founder-operated day-1 loyalty admin flows while keeping the chain default (`x/gov`) when unset.

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
- Faucet service: `tokenchain-faucet.service` (`127.0.0.1:3322`)
- Nginx vhost: `nginx/tokenchain-unified.conf` (single file for all 16 hostnames)

This bootstrap maps both `*.tokenchain.tokentap.ca` and `*.testnet.tokenchain.tokentap.ca`
to the same testnet backend until mainnet is launched.
