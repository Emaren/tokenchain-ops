# TokenChain Relayer Bootstrap

This runbook prepares Hermes for TokenChain testnet and leaves it ready for peer-chain channel setup.

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
# Repeat for peer chain key_name from hermes config
```

## 4) Verify config
```bash
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml config validate
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml keys list --chain tokenchain-testnet-1
```

## 5) Enable service
```bash
cp /var/www/tokenchain-ops/systemd/tokenchain-relayer.service /etc/systemd/system/tokenchain-relayer.service
systemctl daemon-reload
systemctl enable --now tokenchain-relayer
systemctl status tokenchain-relayer --no-pager
```

## 6) Create IBC clients/connections/channels
Use Hermes once peer chain config and funded keys are in place:
```bash
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create client --host-chain tokenchain-testnet-1 --reference-chain <peer-chain-id>
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create connection --a-chain tokenchain-testnet-1 --b-chain <peer-chain-id>
runuser -u tokenchain -- hermes --config /etc/tokenchain/hermes.toml create channel --a-chain tokenchain-testnet-1 --a-connection connection-0 --a-port transfer --b-port transfer --channel-version ics20-1
```
