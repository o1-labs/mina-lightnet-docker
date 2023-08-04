#!/usr/bin/env bash
# set -x

# Exit script when commands fail
set -e
# Kill background process when script exits
trap "killall background" EXIT

LEDGER_FOLDER="$(pwd)/.mina-network/mina-local-network-2-1-1"
GENESIS_LEDGER_CONFIG_FILE=${LEDGER_FOLDER}/daemon.json
ACCOUNTS_MANAGER_EXE="$(pwd)/accounts-manager"
KEYS_FOR_PERMISSIONS_UPDATE=($(pwd)/.mina-network/mina-local-network-2-1-1/libp2p_keys $(pwd)/.mina-network/mina-local-network-2-1-1/offline_fish_keys $(pwd)/.mina-network/mina-local-network-2-1-1/offline_whale_keys $(pwd)/.mina-network/mina-local-network-2-1-1/online_fish_keys $(pwd)/.mina-network/mina-local-network-2-1-1/online_whale_keys $(pwd)/.mina-network/mina-local-network-2-1-1/service-keys $(pwd)/.mina-network/mina-local-network-2-1-1/snark_coordinator_keys $(pwd)/.mina-network/mina-local-network-2-1-1/zkapp_keys $(pwd)/.mina-network/mina-local-network-2-1-1/nodes/fish_0/wallets/store/ $(pwd)/.mina-network/mina-local-network-2-1-1/nodes/node_0/wallets/store/ $(pwd)/.mina-network/mina-local-network-2-1-1/nodes/seed/wallets/store/ $(pwd)/.mina-network/mina-local-network-2-1-1/nodes/whale_0/wallets/store/ $(pwd)/.mina-network/mina-local-network-2-1-1/nodes/whale_1/wallets/store/)

nginx-reload() {
  GRAPHQL_PORT=${1}

  echo 'Updating Nginx configuration...'
  echo ""

  cp -r $(pwd)/nginx.conf /etc/nginx/nginx.conf
  perl -i -p -e "s~###PROXY_PASS###~proxy_pass  http://localhost:${GRAPHQL_PORT}/graphql;~g" /etc/nginx/nginx.conf
  nginx -c /etc/nginx/nginx.conf
  nginx -s reload
}

for ITEM in "${KEYS_FOR_PERMISSIONS_UPDATE[@]}"; do
  chmod 0700 ${ITEM}
  chmod 0600 ${ITEM}/*
done

if [ -f "${ACCOUNTS_MANAGER_EXE}" ]; then
  echo ""
  echo "Starting Accounts-Manager service."
  echo ""

  ${ACCOUNTS_MANAGER_EXE} ${GENESIS_LEDGER_CONFIG_FILE} 8080 &
fi

if [[ $NETWORK_TYPE == "single-node" ]]; then
  echo ""
  echo "Starting Single-Node network."
  echo ""

  echo 'Updating Genesis State timestamp...'
  echo ""
  tmp=$(mktemp)
  jq ".genesis.genesis_state_timestamp=\"$(date +"%Y-%m-%dT%H:%M:%S%z")\"" ${GENESIS_LEDGER_CONFIG_FILE} >"$tmp" && mv -f "$tmp" ${GENESIS_LEDGER_CONFIG_FILE}

  nginx-reload 3085

  MINA_PRIVKEY_PASS="naughty blue worm" \
    MINA_LIBP2P_PASS="naughty blue worm" \
    $(pwd)/mina.exe daemon \
    --config-file ${GENESIS_LEDGER_CONFIG_FILE} \
    --config-directory ${LEDGER_FOLDER}/nodes/whale_0 \
    --libp2p-keypair ${LEDGER_FOLDER}/libp2p_keys/node_0 \
    --block-producer-key ${LEDGER_FOLDER}/online_whale_keys/online_whale_account_0 \
    --run-snark-worker "$(cat ${LEDGER_FOLDER}/snark_coordinator_keys/snark_coordinator_account.pub)" \
    --snark-worker-fee 0.001 \
    --proof-level ${PROOF_LEVEL} \
    --insecure-rest-server \
    --log-json \
    --log-level Trace \
    --file-log-level Trace \
    --demo-mode \
    --seed
elif [[ $NETWORK_TYPE == "multi-node" ]]; then
  echo ""
  echo "Starting Multi-Node network."
  echo ""

  nginx-reload 4006

  bash $(pwd)/mina-local-network.sh -sp 3100 -w 2 -f 1 -n 1 -u -ll Trace -fll Trace -pl ${PROOF_LEVEL}
else
  echo ""
  echo "Unknown network type: $NETWORK_TYPE"
  echo ""

  exit 1
fi

wait
