#!/usr/bin/env bash
set -x
# Exit script when commands fail
set -e

# Parse command line arguments
ARCHS="amd64"
ARCHIVE_NODE_API_VERSION="1.0.0"
DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR="./"
MINA_ACCOUNTS_MANAGER_VERSION="0.1.1"
DOCKER_HUB_USER_NAME=""
MINA_RELEASE="stable"
TARGET_BRANCHES=()
PUSH=1

# Define allowed values for MINA_RELEASE (enum-like behavior)
ALLOWED_MINA_RELEASES=("stable" "nightly" "alpha" "beta")

usage() {
  echo "Usage: $0 [OPTIONS]"
  echo "Options:"
  echo "  --archs ARCHS                                Target architectures (required, default: ${ARCHS}, multiple values separated by comma)"
  echo "  --mina-release RELEASE                       Mina release (default: ${MINA_RELEASE}, allowed: ${ALLOWED_MINA_RELEASES[*]})"
  echo "  --target-branches BRANCH1,BRANCH2,...        Target branches (required only if --mina-release is 'nightly')"
  echo "  --archive-api-version VERSION                Archive-Node-API version (required)"
  echo "  --docker-scripts-dir DIR                     Docker image building scripts directory (required)"
  echo "  --accounts-manager-version VERSION           Mina-Accounts-Manager version (required)"
  echo "  --docker-hub-user USER                       Docker Hub username (required)"
  echo "  -h, --help                                   Show this help message"
}

# Function to check if MINA_RELEASE is valid
is_valid_mina_release() {
  local release="$1"
  for allowed in "${ALLOWED_MINA_RELEASES[@]}"; do
    if [[ "$release" == "$allowed" ]]; then
      return 0
    fi
  done
  return 1
}


while [[ $# -gt 0 ]]; do
  case $1 in
    --archs)
      IFS=',' read -r -a ARCHS <<< "$2"
      shift 2
      ;;
    --archive-api-version)
      ARCHIVE_NODE_API_VERSION="$2"
      shift 2
      ;;
    --docker-scripts-dir)
      DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR="$2"
      shift 2
      ;;
    --accounts-manager-version)
      MINA_ACCOUNTS_MANAGER_VERSION="$2"
      shift 2
      ;;
    --docker-hub-user)
      DOCKER_HUB_USER_NAME="$2"
      shift 2
      ;;
    --skip-push)
      PUSH=0
      shift
      ;;
    --target-branches)
      IFS=',' read -r -a TARGET_BRANCHES <<< "$2"
      shift 2
      ;;
    --mina-release)
      MINA_RELEASE="$2"
      if ! is_valid_mina_release "$MINA_RELEASE"; then
        echo "Error: Invalid MINA_RELEASE value: $MINA_RELEASE. Allowed values: ${ALLOWED_MINA_RELEASES[*]}"
        usage
        exit 1
      fi
      shift 2
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      exit 1
      ;;
  esac
done

# Validate required arguments
if [[ -z "$ARCHIVE_NODE_API_VERSION" ]]; then
  echo "Error: Missing required argument --archive-api-version"
  usage
elif [[ -z "$DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR" ]]; then
  echo "Error: Missing required argument --docker-scripts-dir"
  usage
elif [[ -z "$MINA_ACCOUNTS_MANAGER_VERSION" ]]; then
  echo "Error: Missing required argument --accounts-manager-version"
  usage
elif [[ -z "$DOCKER_HUB_USER_NAME" ]]; then
  echo "Error: Missing required argument --docker-hub-user"
  usage
elif [[ ${#TARGET_BRANCHES[@]} -eq 0 ]]; then
  echo "Error: Missing required argument --target-branches"
  usage
elif ! is_valid_mina_release "$MINA_RELEASE"; then
  echo "Error: Invalid MINA_RELEASE value: $MINA_RELEASE. Allowed values: ${ALLOWED_MINA_RELEASES[*]}"
  usage
  exit 1
fi

START=$(date +%s)

function build-image() {
  local branch_name="$1"
  local arch="$2"

  if [[ -z "$branch_name" ]]; then
    local branch_name_arg=""
  else
    local branch_name_arg="--mina-branch ${branch_name}"
  fi

  echo ""
  echo "[INFO] For Devnet dune profile..."
  echo ""

  # shellcheck disable=SC2046
  SKIP_ARG=$(if [[ $PUSH -eq 1 ]]; then echo ""; else echo "--skip-push"; fi)
  "${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}scripts/build-image.sh" --arch "${arch}" \
      --mina-release "${MINA_RELEASE}" \
      --archive-api-version "${ARCHIVE_NODE_API_VERSION}" \
      --proof-level full \
      --mina-profile devnet \
      ${branch_name_arg} \
      --docker-user "${DOCKER_HUB_USER_NAME}" \
      --tag "${branch_name}-latest-devnet" \
      --accounts-manager-version "${MINA_ACCOUNTS_MANAGER_VERSION}" \
      ${SKIP_ARG}


  echo ""
  echo "[INFO] For Lightnet dune profile..."
  echo ""

  "${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}scripts/build-image.sh" --arch "${arch}" \
      --mina-release "${MINA_RELEASE}" \
      --archive-api-version "${ARCHIVE_NODE_API_VERSION}" \
      --proof-level none \
      --mina-profile devnet-lightnet \
      ${branch_name_arg} \
      --docker-user "${DOCKER_HUB_USER_NAME}" \
      --tag "${branch_name}-latest-lightnet" \
      --accounts-manager-version "${MINA_ACCOUNTS_MANAGER_VERSION}" \
      ${SKIP_ARG}
}


TMP_FOLDER=$(mktemp -d)
KEYS_LOCATION_TARGETS=(${TMP_FOLDER}/mina-local-network-2-1-1/nodes/fish_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/node_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/seed/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/snark_coordinator/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/snark_workers/worker_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/whale_0/wallets/store/ ${TMP_FOLDER}/mina-local-network-2-1-1/nodes/whale_1/wallets/store/)

echo ""
echo "[INFO] Architectures:                     ${ARCHS[*]}"
echo "[INFO] Mina release:                     ${MINA_RELEASE}"
echo "[INFO] Mina branch:                      ${MINA_BRANCH}"
echo "[INFO] Archive-Node-API version:         ${ARCHIVE_NODE_API_VERSION}"
echo "[INFO] Proof level:                      ${PROOF_LEVEL}"
echo "[INFO] Docker Hub user name:             ${DOCKER_HUB_USER_NAME}"
echo "[INFO] Docker Hub image tag:             ${DOCKER_HUB_IMAGE_TAG}"
echo "[INFO] Temporary folder:                 ${TMP_FOLDER}"
echo "[INFO] Accounts Manager version:         ${ACCOUNTS_MANAGER_VERSION}"
echo "[INFO] Target branches:                  ${TARGET_BRANCHES[*]}"
echo "[INFO] Working directory:                ${TMP_FOLDER}"
echo ""

echo "Preparing the filesystem..."
cp -r ./configuration/mina-local-network-2-1-1 ${TMP_FOLDER}/
cp -r ./configuration/Dockerfile ${TMP_FOLDER}/
cp -r ./configuration/nginx.conf ${TMP_FOLDER}/
cp -r ./scripts/spinup-testnet.sh ${TMP_FOLDER}/

for KEYS_LOCATION_TARGET in "${KEYS_LOCATION_TARGETS[@]}"; do
  cp -r ./configuration/key-pairs/* ${KEYS_LOCATION_TARGET}
done

CURRENT_DIR=$PWD

for ARCH in "${ARCHS[@]}"; do
  if [[ "$MINA_RELEASE" == "nightly" ]]; then
    for branch in "${TARGET_BRANCHES[@]}"; do

      build-image "$branch" "$ARCH"
    done
  else
    build-image "" "$ARCH"
  fi
done

echo ""
echo "Cleaning up..."
rm -rf ${TMP_FOLDER}

cd ${CURRENT_DIR}

RUNTIME=$(($(date +%s) - START))


echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo ""
