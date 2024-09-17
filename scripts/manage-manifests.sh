#!/usr/bin/env bash
# set -x
# Exit script when commands fail
set -e

if [[ $# -lt 2 ]]; then
  echo "Usage: $0 <Docker Hub user name> <Target branches>"
  exit 1
fi

START=$(date +%s)
CURRENT_DIR="$(pwd)"

DOCKER_HUB_USER_NAME=${1}
TARGET_BRANCHES=(${2})

echo ""
echo "[INFO] Docker manifests management."
echo ""

for TARGET_BRANCH in "${TARGET_BRANCHES[@]}"; do
  echo ""
  echo "Removing old manifests for branch: '${TARGET_BRANCH}'"
  echo ""
  docker manifest rm ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet || true
  docker manifest rm ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet || true

  echo ""
  echo "Creating new manifests for branch: '${TARGET_BRANCH}'"
  echo ""
  docker manifest create ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet-amd64 ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet-arm64 || true
  docker manifest create ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet-amd64 ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet-arm64 || true

  echo ""
  echo "Annotating new manifests for branch: '${TARGET_BRANCH}'"
  echo ""
  docker manifest annotate ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet-amd64 --os linux --arch amd64 || true
  docker manifest annotate ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet-arm64 --os linux --arch arm64 || true
  docker manifest annotate ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet-amd64 --os linux --arch amd64 || true
  docker manifest annotate ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet-arm64 --os linux --arch arm64 || true

  echo ""
  echo "Pushing new manifests for branch: '${TARGET_BRANCH}'"
  echo ""
  docker manifest push ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-devnet || true
  docker manifest push ${DOCKER_HUB_USER_NAME}/mina-local-network:${TARGET_BRANCH}-latest-lightnet || true
done

END=$(date +%s)
cd ${CURRENT_DIR}
RUNTIME=$(($(date +%s) - START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo ""
