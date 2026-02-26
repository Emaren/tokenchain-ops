# TokenChain Relayer Bootstrap

This runbook prepares Hermes for TokenChain testnet and Osmosis testnet (`osmo-test-5`) channel setup.

## 1) Install Hermes
```bash
cd /tmp
VER="v1.13.3"
curl -fL -o hermes.tar.gz "https://github.com/informalsystems/hermes/releases/download/${VER}/hermes-${VER}-x86_64-unknown-linux-gnu.tar.gz"
tar -xzf hermes.tar.gz
install -m 0755 hermes /usr/local/bin/hermes
hermes --version
```

## 2) Prepare config + state paths
```bash
mkdir -p /etc/tokenchain /var/lib/tokenchain-relayer
chown -R tokenchain:tokenchain /var/lib/tokenchain-relayer
cp /var/www/tokenchain-ops/relayer/hermes-config.toml /etc/tokenchain/hermes.toml
```

## 3) Import relayer keys
Generate keys and fund addresses on both chains before starting Hermes:
```bash
runuser -u tokenchain -- hermes keys add --chain tokenchain-testnet-1 --key-name tokenchain-relayer --mnemonic-file /path/to/tokenchain-relayer.mnemonic
runuser -u tokenchain -- hermes keys add --chain osmo-test-5 --key-name osmosis-relayer --mnemonic-file /path/to/osmosis-relayer.mnemonic
```

Get addresses to fund:
```bash
runuser -u tokenchain -- hermes keys list --chain tokenchain-testnet-1 --json
runuser -u tokenchain -- hermes keys list --chain osmo-test-5 --json
```

Funding:
- TokenChain side: send `utoken` from founder/treasury to `tokenchain-relayer` address.
- Osmosis side: request testnet `uosmo` at [https://faucet.testnet.osmosis.zone](https://faucet.testnet.osmosis.zone) for `osmosis-relayer` address.

## 4) Verify config + health
```bash
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml config validate
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml keys list --chain tokenchain-testnet-1
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml keys list --chain osmo-test-5
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml health-check
```

## 5) Enable service
```bash
cp /var/www/tokenchain-ops/systemd/tokenchain-relayer.service /etc/systemd/system/tokenchain-relayer.service
systemctl daemon-reload
systemctl enable --now tokenchain-relayer
systemctl status tokenchain-relayer --no-pager
```

## 6) Create IBC clients/connections/channels
Use Hermes once both relayer keys are funded:
```bash
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create client --host-chain tokenchain-testnet-1 --reference-chain osmo-test-5
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create connection --a-chain tokenchain-testnet-1 --b-chain osmo-test-5
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create channel --a-chain tokenchain-testnet-1 --a-connection connection-0 --a-port transfer --b-port transfer --channel-version ics20-1
```

Optional explicit channel query:
```bash
curl -sS 'https://rest.testnet.tokenchain.tokentap.ca/ibc/core/channel/v1/channels?pagination.limit=50' | jq .
```

One-shot helper after keys are funded:
```bash
/var/www/tokenchain-ops/scripts/setup-osmo-ibc.sh
```
