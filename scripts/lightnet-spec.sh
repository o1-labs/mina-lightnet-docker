#!/usr/bin/env bash

# Prints the minimina network spec of the container's network, from the
# container's environment (NETWORK_TYPE, RUN_ARCHIVE_NODE, LOG_LEVEL,
# SLOT_TIME, POSTGRES_DB). spinup-testnet.sh creates the network from it.
#
# Ports are those of the network mina-local-network.sh used to start:
#   single-node: one daemon, GraphQL on 3085; mina-archive on 3089
#   multi-node:  seed 3101, whales 4001 and 4006, fish 5001, plain node 6001,
#                snark coordinator 7001 (GraphQL ports)
# and the services: accounts manager on 8181, Archive-Node-API on 8282.

set -euo pipefail

NETWORK_TYPE="${NETWORK_TYPE:-single-node}"
RUN_ARCHIVE_NODE="${RUN_ARCHIVE_NODE:-true}"
LOG_LEVEL="${LOG_LEVEL:-Trace}"
SLOT_TIME="${SLOT_TIME:-20000}"
POSTGRES_DB="${POSTGRES_DB:-archive}"
# The accounts of the genesis ledger and their key files (see the Dockerfile).
LIGHTNET_DIR="${LIGHTNET_DIR:-${HOME}/lightnet}"
# The profile the image's daemon runs with: the one the image wrote, else the deb's.
PROFILE="${PROFILE:-$(cat /etc/coda/build_config/PROFILE 2>/dev/null || echo devnet)}"
# The image's own builds; empty: minimina installs its release.
ACCOUNTS_MANAGER_BIN="${ACCOUNTS_MANAGER_BIN-$(command -v accounts-manager || true)}"
ARCHIVE_NODE_API_BIN="${ARCHIVE_NODE_API_BIN-$(command -v mina-archive-node-graphql || true)}"

bin() {
  if [[ -n "${1}" ]]; then
    echo "bin = \"${1}\""
  fi
}

cat <<EOF
profile = "${PROFILE}"
log_level = "${LOG_LEVEL}"

# block producers and libp2p keys: the same on every start
[keys]
seed = "lightnet"

[ledger]
# the 1000 prefunded accounts, with their private keys
file = "${LIGHTNET_DIR}/accounts.json"

[runtime_config.proof]
block_window_duration_ms = ${SLOT_TIME}
EOF

if [[ "${NETWORK_TYPE}" == "single-node" ]]; then
  GRAPHQL_NODE="single-node"
  cat <<EOF

# seed, block producer and snark worker in one daemon
[[nodes]]
role = "standalone"
name = "single-node"
client_port = 3084
EOF
else
  GRAPHQL_NODE="whale_1"
  cat <<EOF

[[nodes]]
role = "seed"
name = "seed"
client_port = 3100

[[nodes]]
role = "block-producer"
name = "whale_0"
client_port = 4000

[[nodes]]
role = "block-producer"
name = "whale_1"
client_port = 4005

[[nodes]]
role = "block-producer"
name = "fish_0"
client_port = 5000
balance = "65500"

[[nodes]]
role = "plain"
name = "node_0"
client_port = 6000

[[nodes]]
role = "snark-coordinator"
name = "snark_coordinator"
client_port = 7000
workers = 2
EOF
fi

if [[ "${RUN_ARCHIVE_NODE}" == "true" ]]; then
  cat <<EOF

[[nodes]]
role = "archive"
name = "archive"
database = "${POSTGRES_DB}"
archive_port = 3089
EOF
  if [[ "${NETWORK_TYPE}" != "single-node" ]]; then
    echo "client_port = 3110"
  fi
  cat <<EOF

[[nodes]]
role = "archive-node-api"
name = "archive-node-api"
client_port = 8282
$(bin "${ARCHIVE_NODE_API_BIN}")
EOF
fi

cat <<EOF

# o1js Lightnet.acquireKeyPair: hands out the accounts of [ledger] file
[[nodes]]
role = "accounts-manager"
name = "accounts-manager"
client_port = 8181
node = "${GRAPHQL_NODE}"
keys = "${LIGHTNET_DIR}/key-pairs"
$(bin "${ACCOUNTS_MANAGER_BIN}")
EOF
