#!/usr/bin/env bash

# Container entrypoint: starts PostgreSQL and NGINX, then the network with
# minimina (https://github.com/o1-labs/minimina): the Mina daemons, the
# archive node, Archive-Node-API and the accounts manager, from the spec
# lightnet-spec.sh prints.

set -x

# Exit script when commands fail
set -e

NETWORK=lightnet
NETWORK_DIR="${HOME}/.minimina/${NETWORK}"
SPEC_FILE="${HOME}/lightnet/network.toml"
LOGS_DIR="${HOME}/logs"
RDBMS_PORT=5432
# The postgres server minimina makes the archive database on
export MINIMINA_POSTGRES_URI="postgresql://${POSTGRES_USER}:${POSTGRES_PASSWORD}@127.0.0.1:${RDBMS_PORT}"

mkdir -p "${LOGS_DIR}"

wait-for-service() {
  echo ""
  while ! nc -z 127.0.0.1 ${1}; do
    echo "Waiting for the service (:${1}) to be ready..."
    sleep 5
  done
  echo ""
}

start-rdbms() {
  echo ""
  echo "Starting the RDBMS service..."
  echo ""
  echo "export PATH=$PATH" >>/etc/profile
  # POSTGRES_DB=postgres: minimina makes the archive database (POSTGRES_DB)
  # itself, and never drops a database it did not make
  su - postgres -c "POSTGRES_USER=${POSTGRES_USER} POSTGRES_PASSWORD=${POSTGRES_PASSWORD} POSTGRES_DB=postgres PGDATA=/var/lib/postgresql/data /usr/local/bin/docker-entrypoint.sh postgres &"
  wait-for-service ${RDBMS_PORT}
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

# Links the log files where they were before minimina (zkapp-cli reads them
# there): /root/logs and, for multi-node, the node directories of
# mina-local-network.sh.
link-logs() {
  local logs="${NETWORK_DIR}/logs"
  ln -sf "${logs}/archive-node-api.log" "${LOGS_DIR}/archive-node-api.log"
  ln -sf "${logs}/accounts-manager.log" "${LOGS_DIR}/accounts-manager.log"
  if [[ $NETWORK_TYPE == "single-node" ]]; then
    ln -sf "${logs}/single-node.log" "${LOGS_DIR}/single-node-network.log"
    ln -sf "${logs}/single-node-archive.log" "${LOGS_DIR}/archive-node.log"
  else
    local nodes="${HOME}/.mina-network/mina-local-network-2-1-1/nodes"
    for node in seed whale_0 whale_1 fish_0 node_0 snark_coordinator; do
      mkdir -p "${nodes}/${node}"
      ln -sf "${logs}/${node}.log" "${nodes}/${node}/log.txt"
    done
    mkdir -p "${nodes}/snark_workers/worker_0" "${nodes}/archive"
    ln -sf "${logs}/snark_worker-1.log" "${nodes}/snark_workers/worker_0/log.txt"
    ln -sf "${logs}/archive-archive.log" "${nodes}/archive/log.txt"
  fi
}

# Validate that the requested proof level is compatible with the compiled binary
if [[ -n "${COMPILED_PROOF_LEVEL}" ]] && [[ "${PROOF_LEVEL}" != "${COMPILED_PROOF_LEVEL}" ]]; then
  echo ""
  echo "ERROR: Requested PROOF_LEVEL='${PROOF_LEVEL}' is not compatible with this image."
  echo "       This image was built with proof_level='${COMPILED_PROOF_LEVEL}'."
  if [[ "${COMPILED_PROOF_LEVEL}" == "none" ]]; then
    echo "       This is a lightnet image (no proofs). Use the devnet image for PROOF_LEVEL=full."
  fi
  echo ""
  exit 1
fi

if [[ $RUN_ARCHIVE_NODE == "true" ]]; then
  start-rdbms
fi

# Development-network defaults for @o1-labs/mina-archive-node-graphql >= 2.0.0,
# which is secure-by-default: no CORS, no introspection, no GraphiQL and a
# per-IP rate limit. A local test network wants all of them open.
# Override any of them with --env on `docker run`. minimina starts the server
# with this environment.
export CORS_ORIGIN="${ARCHIVE_API_CORS_ORIGIN:-*}"
export ENABLE_INTROSPECTION="${ARCHIVE_API_ENABLE_INTROSPECTION:-true}"
export ENABLE_GRAPHIQL="${ARCHIVE_API_ENABLE_GRAPHIQL:-true}"
export ENABLE_ZKAPP_COMMANDS_QUERY="${ARCHIVE_API_ENABLE_ZKAPP_COMMANDS_QUERY:-true}"
export ENABLE_BLOCK_TRANSACTION_DETAILS="${ARCHIVE_API_ENABLE_BLOCK_TRANSACTION_DETAILS:-true}"
export RATE_LIMIT_MAX="${ARCHIVE_API_RATE_LIMIT_MAX:-0}"

echo ""
echo "Creating the ${NETWORK_TYPE} network..."
echo ""
"${HOME}/lightnet-spec.sh" >"${SPEC_FILE}"
cat "${SPEC_FILE}"
# a fresh network on every start of the container, as before; the processes
# of a previous start are gone with it
rm -rf "${NETWORK_DIR}"
minimina --mode native --bin-path "$(dirname "$(command -v mina)")" \
  network create -n "${NETWORK}" --spec "${SPEC_FILE}"

if [[ $NETWORK_TYPE == "single-node" ]]; then
  # Redirect 8080 to 3085 (daemon rest port) for single-node networks
  nginx-reload 3085
else
  # 8080 is whale_1's GraphQL, as before
  nginx-reload 4006
fi

echo ""
echo "Starting the ${NETWORK_TYPE} network."
echo ""
minimina network start -n "${NETWORK}"
link-logs

stop-network() {
  minimina network stop -n "${NETWORK}" || true
  exit 0
}
trap stop-network TERM INT

# the processes' logs are the container's log
tail -n +1 -F "${NETWORK_DIR}"/logs/*.log &
wait $!
