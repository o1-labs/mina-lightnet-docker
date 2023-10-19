#!/usr/bin/env bash
# set -x

# Exit script when commands fail
set -e
# Kill background process when script exits
trap "killall background" EXIT

ARCHIVE_NODE_PORT=3086
RDBMS_PORT=5432
ARCHIVE_NODE_API_PORT=8282
ARCHIVE_NODE_API_LOG_FILE_PATH=${HOME}/logs/archive-node-api.log
LEDGER_FOLDER="${HOME}/.mina-network/mina-local-network-2-1-1"
GENESIS_LEDGER_CONFIG_FILE=${LEDGER_FOLDER}/daemon.json
ACCOUNTS_MANAGER_EXE="${HOME}/accounts-manager"
KEYS_FOR_PERMISSIONS_UPDATE=(${HOME}/.mina-network/mina-local-network-2-1-1/libp2p_keys ${HOME}/.mina-network/mina-local-network-2-1-1/offline_fish_keys ${HOME}/.mina-network/mina-local-network-2-1-1/offline_whale_keys ${HOME}/.mina-network/mina-local-network-2-1-1/online_fish_keys ${HOME}/.mina-network/mina-local-network-2-1-1/online_whale_keys ${HOME}/.mina-network/mina-local-network-2-1-1/service-keys ${HOME}/.mina-network/mina-local-network-2-1-1/snark_coordinator_keys ${HOME}/.mina-network/mina-local-network-2-1-1/zkapp_keys ${HOME}/.mina-network/mina-local-network-2-1-1/nodes/fish_0/wallets/store/ ${HOME}/.mina-network/mina-local-network-2-1-1/nodes/node_0/wallets/store/ ${HOME}/.mina-network/mina-local-network-2-1-1/nodes/seed/wallets/store/ ${HOME}/.mina-network/mina-local-network-2-1-1/nodes/whale_0/wallets/store/ ${HOME}/.mina-network/mina-local-network-2-1-1/nodes/whale_1/wallets/store/)

wait-for-service() {
  echo ""
  while ! nc -z localhost ${1}; do
    echo "Waiting for the service (:${1}) to be ready..."
    sleep 5
  done
  echo ""
}

prepare-rdbms() {
  echo ""
  echo "Starting the RDBMS service..."
  echo ""
  echo "export PATH=$PATH" >>/etc/profile
  su - postgres -c "POSTGRES_USER=${POSTGRES_USER} POSTGRES_PASSWORD=${POSTGRES_PASSWORD} POSTGRES_DB=${POSTGRES_DB} PGDATA=/var/lib/postgresql/data /usr/local/bin/docker-entrypoint.sh postgres &"
  wait-for-service ${RDBMS_PORT}

  echo "Updating the Archive Node RDBMS schema..."
  echo ""
  psql postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${RDBMS_PORT}/${POSTGRES_DB} <create_schema.sql
  echo ""
}

start-archive-node-api() {
  echo ""
  echo "Starting the Archive-Node-API service..."
  echo "Archive-Node-API log file: ${ARCHIVE_NODE_API_LOG_FILE_PATH}"
  echo ""
  cd ${HOME}/Archive-Node-API/
  npm run start >${ARCHIVE_NODE_API_LOG_FILE_PATH} 2>&1 &
  cd ../
  wait-for-service ${ARCHIVE_NODE_API_PORT}
  echo ""
}

nginx-reload() {
  GRAPHQL_PORT=${1}

  echo "Updating the Nginx configuration..."
  echo ""

  cp -r ${HOME}/nginx.conf /etc/nginx/nginx.conf
  perl -i -p -e "s~###PROXY_PASS###~proxy_pass  http://localhost:${GRAPHQL_PORT}/graphql;~g" /etc/nginx/nginx.conf
  nginx -c /etc/nginx/nginx.conf
  nginx -s reload
}

for ITEM in "${KEYS_FOR_PERMISSIONS_UPDATE[@]}"; do
  chmod 0700 ${ITEM}
  chmod 0600 ${ITEM}/*
done

if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
  prepare-rdbms
  start-archive-node-api
fi

if [ -f "${ACCOUNTS_MANAGER_EXE}" ]; then
  echo ""
  echo "Starting the Accounts-Manager service..."
  echo ""

  ${ACCOUNTS_MANAGER_EXE} ${GENESIS_LEDGER_CONFIG_FILE} 8080 &
fi

if [[ $NETWORK_TYPE == "single-node" ]]; then
  mkdir -p ${HOME}/logs || true
  ARCHIVE_LOG_FILE_PATH=${HOME}/logs/archive-node-network.log
  DAEMON_LOG_FILE_PATH=${HOME}/logs/single-node-network.log
  ARCHIVE_CLI_ARGS=""

  echo ""
  echo "Starting Single-Node network."
  echo ""

  echo "Updating the Genesis State timestamp..."
  echo ""
  tmp=$(mktemp)
  jq ".genesis.genesis_state_timestamp=\"$(date +"%Y-%m-%dT%H:%M:%S%z")\"" ${GENESIS_LEDGER_CONFIG_FILE} >"$tmp" && mv -f "$tmp" ${GENESIS_LEDGER_CONFIG_FILE}

  nginx-reload 3085

  if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
    ARCHIVE_CLI_ARGS="--archive-address ${ARCHIVE_NODE_PORT}"

    echo "Starting the Archive Node..."
    echo "Mina Archive node log file: ${ARCHIVE_LOG_FILE_PATH}"
    echo ""
    ${HOME}/archive.exe run \
      --config-file ${GENESIS_LEDGER_CONFIG_FILE} \
      --log-level Trace \
      --postgres-uri postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@localhost:${RDBMS_PORT}/${POSTGRES_DB} \
      --server-port ${ARCHIVE_NODE_PORT} >${ARCHIVE_LOG_FILE_PATH} 2>&1 &
    wait-for-service ${ARCHIVE_NODE_PORT}
  fi

  echo "Starting the Mina Daemon..."
  echo "Mina Daemon log file: ${DAEMON_LOG_FILE_PATH}"
  echo ""
  MINA_PRIVKEY_PASS="naughty blue worm" \
    MINA_LIBP2P_PASS="naughty blue worm" \
    ${HOME}/mina.exe daemon \
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
    --seed ${ARCHIVE_CLI_ARGS} >${DAEMON_LOG_FILE_PATH} 2>&1
elif [[ $NETWORK_TYPE == "multi-node" ]]; then
  ARCHIVE_CLI_ARGS=""

  echo ""
  echo "Starting Multi-Node network."
  echo ""

  nginx-reload 4006

  if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
    ARCHIVE_CLI_ARGS=" --archive --pg-user ${POSTGRES_USER} --pg-passwd ${POSTGRES_PASSWORD} --pg-db ${POSTGRES_DB}"
  fi

  bash ${HOME}/mina-local-network.sh -sp 3100 -w 2 -f 1 -n 1 -u -ll Trace -fll Trace -pl ${PROOF_LEVEL}${ARCHIVE_CLI_ARGS}
else
  echo ""
  echo "Unknown network type: $NETWORK_TYPE"
  echo ""

  exit 1
fi

wait
