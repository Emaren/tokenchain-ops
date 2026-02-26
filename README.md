# tokenchain-ops

Operational configs and runbooks for TokenChain.

## Contents
- `nginx/` reverse-proxy vhosts for web, API, RPC, REST, and explorer
- `systemd/` service units for chain, indexer, relayer
- `relayer/` Hermes configuration templates
- `runbooks/` deployment and incident response notes
- `scripts/` helper scripts for sync/deploy

## DNS model
Mainnet hostnames (recommended):
- `tokenchain.tokentap.ca`
- `api.tokenchain.tokentap.ca`
- `rpc.tokenchain.tokentap.ca`
- `rest.tokenchain.tokentap.ca`
- `grpc.tokenchain.tokentap.ca` (DNS-only/non-proxied)
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
