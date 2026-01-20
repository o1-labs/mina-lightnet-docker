#!/usr/bin/env bash
set -x
# Exit script when commands fail
set -e

# Parse command line arguments
ARCHS="amd64"
ARCHIVE_NODE_API_VERSION="0.0.8"
DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR="./"
MINA_ACCOUNTS_MANAGER_VERSION="0.1.1"
DOCKER_HUB_USER_NAME=""
TARGET_BRANCHES=()
PUSH=1
EXTRA_DOCKER_SUFFIX=""
NO_CACHE=0

# Define allowed values for MINA_RELEASE (enum-like behavior)
# Since devnet profile is not promoted to stable release, we limit the allowed values.
# Nightly -> represents cutting edge builds from develop branch
# Alpha   -> represents pre-release builds for testing
# Beta    -> represents release candidate builds for final verification, which usually precede stable releases.
ALLOWED_MINA_RELEASES=("nightly" "alpha" "beta")

MINA_RELEASE=${ALLOWED_MINA_RELEASES[0]}

# Define standard Mina branches
# These are the branches considered standard for Mina development
# and they don't require special handling, like specifying profile different than devnet.
STANDARD_MINA_BRANCHES=("develop" "compatible" "master")

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
  echo "  --skip-push                                  Skip pushing images to Docker Hub"
  echo "  --extra-docker-suffix SUFFIX                 Extra suffix to append to Docker image tags"
  echo "  --no-cache                                   Disable Docker build cache"
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
      ARCHS="$2"
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
    --extra-docker-suffix)
      EXTRA_DOCKER_SUFFIX="$2"
      shift 2
      ;;
    --no-cache)
      NO_CACHE=1
      shift
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

# Additional condition: when MINA_RELEASE is not 'nightly', TARGET_BRANCHES can only be 'master'
if [[ "$MINA_RELEASE" != "nightly" ]]; then
  for branch in "${TARGET_BRANCHES[@]}"; do
    if [[ "$branch" != "master" ]]; then
      echo "Error: When --mina-release is not 'nightly', --target-branches can only be 'master'. Found: $branch"
      usage
      exit 1
    fi
  done
fi



START=$(date +%s)

function build-image() {
  local branch_name="$1"
  local archs="$2"

  if [[ -z "$branch_name" ]]; then
    local branch_name_arg=""
  else
    local branch_name_arg="--mina-branch ${branch_name}"
  fi

 

  # Construct tag suffix
  local tag_suffix=""
  if [[ -n "$EXTRA_DOCKER_SUFFIX" ]]; then
    tag_suffix="-${EXTRA_DOCKER_SUFFIX}"
  fi

  # Determine profile names based on branch
  local profile_devnet="devnet"
  local profile_lightnet="lightnet"
  if [[ -n "$branch_name" ]]; then
    local is_standard=0
    for std_branch in "${STANDARD_MINA_BRANCHES[@]}"; do
      if [[ "$branch_name" == "$std_branch" ]]; then
        is_standard=1
        break
      fi
    done
    if [[ $is_standard -eq 0 ]]; then
      profile_devnet="$branch_name"
    fi
  fi

  echo ""
  echo "[INFO] For $profile_devnet profile..."
  echo ""

  NO_CACHE_ARG=$(if [[ $NO_CACHE -eq 1 ]]; then echo "--no-cache"; else echo ""; fi)

  # shellcheck disable=SC2046
  SKIP_ARG=$(if [[ $PUSH -eq 1 ]]; then echo ""; else echo "--skip-push"; fi)
  "${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}scripts/build-image.sh" --archs "${archs}" \
      --mina-release "${MINA_RELEASE}" \
      --archive-api-version "${ARCHIVE_NODE_API_VERSION}" \
      --proof-level full \
      --mina-profile "$profile_devnet" \
      ${branch_name_arg} \
      --docker-user "${DOCKER_HUB_USER_NAME}" \
      --tag "${branch_name}-latest-devnet${tag_suffix}" \
      --accounts-manager-version "${MINA_ACCOUNTS_MANAGER_VERSION}" \
      ${SKIP_ARG} ${NO_CACHE_ARG}

  echo ""
  echo "[INFO] For $profile_lightnet profile..."
  echo ""

  "${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}scripts/build-image.sh" --archs "${archs}" \
      --mina-release "${MINA_RELEASE}" \
      --archive-api-version "${ARCHIVE_NODE_API_VERSION}" \
      --proof-level none \
      --mina-profile "$profile_devnet" \
      --mina-extra-profile "$profile_lightnet" \
      ${branch_name_arg} \
      --docker-user "${DOCKER_HUB_USER_NAME}" \
      --tag "${branch_name}-latest-lightnet${tag_suffix}" \
      --accounts-manager-version "${MINA_ACCOUNTS_MANAGER_VERSION}" \
      ${SKIP_ARG} ${NO_CACHE_ARG}
}


TMP_FOLDER=$(mktemp -d)
KEYS_LOCATION_TARGETS=(${TMP_FOLDER}/mina-local-network/nodes/fish_0/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/node_0/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/seed/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/snark_coordinator/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/snark_workers/worker_0/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/whale_0/wallets/store/ ${TMP_FOLDER}/mina-local-network/nodes/whale_1/wallets/store/)

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
cp -r ./configuration/mina-local-network ${TMP_FOLDER}/
cp -r ./configuration/Dockerfile ${TMP_FOLDER}/
cp -r ./configuration/nginx.conf ${TMP_FOLDER}/
cp -r ./scripts/spinup-testnet.sh ${TMP_FOLDER}/

for KEYS_LOCATION_TARGET in "${KEYS_LOCATION_TARGETS[@]}"; do
  cp -r ./configuration/key-pairs/* ${KEYS_LOCATION_TARGET}
done

CURRENT_DIR=$PWD

if [[ "$MINA_RELEASE" == "nightly" ]]; then
  for branch in "${TARGET_BRANCHES[@]}"; do
    build-image "$branch" "${ARCHS[@]}"
  done
else
  build-image "master" "${ARCHS[@]}"
fi

echo ""
echo "Cleaning up..."
rm -rf ${TMP_FOLDER}

cd ${CURRENT_DIR}

RUNTIME=$(($(date +%s) - START))


echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo ""
