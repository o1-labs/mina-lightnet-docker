#!/usr/bin/env bash

set -x

# Exit script when commands fail
set -e
# Kill background process when script exits
trap "killall background" EXIT

RDBMS_PORT=5432
ARCHIVE_NODE_API_PORT=8282
ARCHIVE_NODE_API_LOG_FILE_PATH=${HOME}/logs/archive-node-api.log
LEDGER_FOLDER="${HOME}/.mina-network/mina-local-network-2-1-1"
GENESIS_LEDGER_CONFIG_FILE=${LEDGER_FOLDER}/daemon.json


KEYS_FOR_PERMISSIONS_UPDATE=(${HOME}/.mina-network/mina-local-network-2-1-1/libp2p_keys ${HOME}/.mina-network/mina-local-network-2-1-1/offline_fish_keys ${HOME}/.mina-network/mina-local-network-2-1-1/offline_whale_keys ${HOME}/.mina-network/mina-local-network-2-1-1/online_fish_keys ${HOME}/.mina-network/mina-local-network-2-1-1/online_whale_keys ${HOME}/.mina-network/mina-local-network-2-1-1/service-keys ${HOME}/.mina-network/mina-local-network-2-1-1/snark_coordinator_keys ${HOME}/.mina-network/mina-local-network-2-1-1/zkapp_keys )

mkdir -p ${HOME}/logs || true

wait-for-service() {
  echo ""
  while ! nc -z 127.0.0.1 ${1}; do
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
  psql postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${RDBMS_PORT}/${POSTGRES_DB} < /etc/mina/archive/create_schema.sql
  echo ""
}

start-archive-node-api() {
  echo ""
  echo "Starting the Archive-Node-API service..."
  echo "Archive-Node-API log file: ${ARCHIVE_NODE_API_LOG_FILE_PATH}"
  echo ""
  PORT=${ARCHIVE_NODE_API_PORT} PG_CONN="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${RDBMS_PORT}/${POSTGRES_DB}" archive-node-api >${ARCHIVE_NODE_API_LOG_FILE_PATH} 2>&1 &
  wait-for-service ${ARCHIVE_NODE_API_PORT}
  echo ""
}

nginx-reload() {
  GRAPHQL_PORT=${1}

  echo "Updating the Nginx configuration..."
  echo ""

  cp -r ${HOME}/nginx.conf /etc/nginx/nginx.conf
  perl -i -p -e "s~###PROXY_PASS###~proxy_pass  http://127.0.0.1:${GRAPHQL_PORT}/graphql;~g" /etc/nginx/nginx.conf
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

if [[ $NETWORK_TYPE == "single-node" ]]; then
  LEDGER_FOLDER="${HOME}/.mina-network/mina-local-network-2-1-1"
elif [[ $NETWORK_TYPE == "multi-node" ]]; then
  LEDGER_FOLDER="${HOME}/.mina-network/mina-local-network-demo"
else
  echo ""
  echo "Unknown network type: $NETWORK_TYPE"
  echo ""

  exit 1
fi

GENESIS_LEDGER_CONFIG_FILE=${LEDGER_FOLDER}/daemon.json

echo ""
echo "Starting the Accounts-Manager service..."
echo ""

"accounts-manager" "${GENESIS_LEDGER_CONFIG_FILE}" 8181 3101 "naughty blue worm" &

if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
    ARCHIVE_CLI_ARGS=" --archive --pg-user ${POSTGRES_USER} --pg-passwd ${POSTGRES_PASSWORD} --pg-db ${POSTGRES_DB}"
else
    ARCHIVE_CLI_ARGS=""
fi

export MINA_EXE=mina
export ARCHIVE_EXE=mina-archive
export LOGPROC_EXE=mina-logproc

if [[ $NETWORK_TYPE == "single-node" ]]; then

  # Redirect 8080 to 3101 (daemon rest port) for single-node networks
  nginx-reload 3101

  echo ""
  echo "Starting Single-Node network."
  echo ""

  bash ${HOME}/scripts/mina-local-network/mina-local-network.sh -sp 3100 --demo -u -ll ${LOG_LEVEL} -fll ${LOG_LEVEL} --override-slot-time ${SLOT_TIME} -pl ${PROOF_LEVEL}${ARCHIVE_CLI_ARGS}

elif [[ $NETWORK_TYPE == "multi-node" ]]; then

  #TODO: Find out why Nginx needs to be reloaded twice to work properly and why 4006 ?
  nginx-reload 4006

  echo ""
  echo "Starting Multi-Node network."
  echo ""

  if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
    ARCHIVE_CLI_ARGS=" --archive --pg-user ${POSTGRES_USER} --pg-passwd ${POSTGRES_PASSWORD} --pg-db ${POSTGRES_DB}"
  fi

  bash ${HOME}/scripts/mina-local-network/mina-local-network.sh -sp 3100 -w 2 -f 1 -n 1 -u -ll ${LOG_LEVEL} -fll ${LOG_LEVEL} --override-slot-time ${SLOT_TIME} -pl ${PROOF_LEVEL}${ARCHIVE_CLI_ARGS}
else
  echo ""
  echo "Unknown network type: $NETWORK_TYPE"
  echo ""

  exit 1
fi

wait
