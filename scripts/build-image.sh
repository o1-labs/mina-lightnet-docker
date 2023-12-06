#!/usr/bin/env bash
# set -x
# Exit script when commands fail
set -e

if [[ $# -lt 6 ]]; then
  echo "Usage: $0 <Architecture> <Mina repository root path> <Archive-Node-API repository root path> <Proof level> <Docker Hub user name> <Docker Hub image tag> [<Accounts-Manager binary path>]"
  exit 1
fi

START=$(date +%s)
CURRENT_DIR="$(pwd)"

ARCH=${1}
MINA_REPO_DIR=${2}
ARCHIVE_NODE_API_REPO_DIR=${3}
PROOF_LEVEL=${4}
DOCKER_HUB_USER_NAME=${5}
DOCKER_HUB_IMAGE_TAG=${6}
TMP_FOLDER=$(mktemp -d)
KEYS_LOCATION_TARGETS=(${TMP_FOLDER}/mina-local-network-2-1-1/nodes/fish_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/node_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/seed/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/snark_coordinator/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/snark_workers/worker_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/whale_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/whale_1/wallets/store/)

echo ""
echo "[INFO] Architecture: ${ARCH}"
echo "[INFO] Mina repository root: ${MINA_REPO_DIR}"
echo "[INFO] Archive-Node-API repository root: ${ARCHIVE_NODE_API_REPO_DIR}"
echo "[INFO] Proof level: ${PROOF_LEVEL}"
echo "[INFO] Docker Hub user name: ${DOCKER_HUB_USER_NAME}"
echo "[INFO] Docker Hub image tag: ${DOCKER_HUB_IMAGE_TAG}"
echo "[INFO] Temporary folder: ${TMP_FOLDER}"
echo ""

echo "Preparing the filesystem..."
cp -r ./configuration/mina-local-network-2-1-1 ${TMP_FOLDER}/
cp -r ./configuration/Dockerfile ${TMP_FOLDER}/
cp -r ./configuration/nginx.conf ${TMP_FOLDER}/
cp -r ./scripts/spinup-testnet.sh ${TMP_FOLDER}/
for KEYS_LOCATION_TARGET in "${KEYS_LOCATION_TARGETS[@]}"; do
  cp -r ./configuration/key-pairs/* ${KEYS_LOCATION_TARGET}
done
cp -r ${MINA_REPO_DIR}/scripts/mina-local-network/mina-local-network.sh ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/src/app/archive/drop_tables.sql ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/src/app/archive/create_schema.sql ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/src/app/archive/zkapp_tables.sql ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/_build/default/src/app/cli/src/mina.exe ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/src/app/libp2p_helper/result/bin/libp2p_helper ${TMP_FOLDER}/
cp -r ${MINA_REPO_DIR}/_build/default/src/app/archive/archive.exe ${TMP_FOLDER}/
# cp -r ${MINA_REPO_DIR}/_build/default/src/app/logproc/logproc.exe ${TMP_FOLDER}/
# cp -r ${MINA_REPO_DIR}/_build/default/src/app/zkapp_test_transaction/zkapp_test_transaction.exe ${TMP_FOLDER}/
cp -r ${ARCHIVE_NODE_API_REPO_DIR} ${TMP_FOLDER}
cp -r ./configuration/archive-node-api.env ${TMP_FOLDER}/Archive-Node-API/.env
if [[ $# -eq 7 ]]; then
  cp -r ${7} ${TMP_FOLDER}/
  perl -i -p -e 's~# COPY accounts-manager /root/~COPY accounts-manager /root/~g' ${TMP_FOLDER}/Dockerfile
  perl -i -p -e 's~# RUN chmod \+x accounts-manager~RUN chmod \+x accounts-manager~g' ${TMP_FOLDER}/Dockerfile
  perl -i -p -e 's~# EXPOSE 8181~EXPOSE 8181~g' ${TMP_FOLDER}/Dockerfile
fi

echo ""
echo "Updating local network manager paths..."
perl -i -p -e 's~_build/default/src/app/cli/src/mina.exe~\./mina.exe~g' ${TMP_FOLDER}/mina-local-network.sh
perl -i -p -e 's~_build/default/src/app/archive/archive.exe~\./archive.exe~g' ${TMP_FOLDER}/mina-local-network.sh
perl -i -p -e 's~_build/default/src/app/logproc/logproc.exe~\./logproc.exe~g' ${TMP_FOLDER}/mina-local-network.sh
perl -i -p -e 's~_build/default/src/app/zkapp_test_transaction/zkapp_test_transaction.exe~\./zkapp_test_transaction.exe~g' ${TMP_FOLDER}/mina-local-network.sh

echo ""
echo "Building the Docker image..."
echo ""
cd ${TMP_FOLDER}
docker rmi -f ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH} || true
docker rmi -f mina-local-network || true
docker build --platform linux/${ARCH} -t mina-local-network --build-arg="PROOF_LEVEL=${PROOF_LEVEL}" .

echo ""
echo "Publishing the Docker image..."
docker tag mina-local-network ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH}
docker push ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH}

echo ""
echo "Cleaning up..."
rm -rf ${TMP_FOLDER}

END=$(date +%s)
cd ${CURRENT_DIR}
RUNTIME=$(($(date +%s) - START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo "[INFO] Docker Hub link: https://hub.docker.com/r/${DOCKER_HUB_USER_NAME}/mina-local-network/tags"
echo ""
