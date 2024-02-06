#!/usr/bin/env bash
# set -x
# Exit script when commands fail
# set -e

if [[ $# -lt 7 ]]; then
  echo "Usage: $0 <Architecture> <Mina repository root path> <Archive-Node-API repository root path> <Docker image building scripts repository root path> <Mina-Accounts-Manager repository root path> <Docker Hub user name> <Target branches>"
  exit 1
fi

# https://community.hetzner.com/tutorials/resize-ext-partition

START=$(date +%s)
CURRENT_DIR="$(pwd)"

ARCH=${1}
MINA_REPO_DIR=${2}
ARCHIVE_NODE_API_REPO_DIR=${3}
DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR=${4}
MINA_ACCOUNTS_MANAGER_VERSION=${5}
DOCKER_HUB_USER_NAME=${6}
TARGET_BRANCHES=(${7})
MINA_ACCOUNTS_MANAGER_LINK=https://github.com/shimkiv/mina-accounts-manager/releases/download/${MINA_ACCOUNTS_MANAGER_VERSION}/accounts-manager-${ARCH}

cd ${MINA_REPO_DIR}
cd ../
GIT_PULL_ALL_DIR=$(pwd)
cd ${CURRENT_DIR}

gitPullAll() {
  for DIR in $(find ${GIT_PULL_ALL_DIR} -maxdepth 1 -mindepth 1 -type d); do
    cd ${DIR}
    echo ""
    echo "Updating the \"$(pwd)\" repo:"
    # if [[ ${DIR} == *"mina" ]]; then
    #   cd src/lib/o1js/src/bindings
    #   git stash
    #   cd ../../../../../
    #   cd src/lib/o1js
    #   git stash
    #   git submodule sync
    #   git submodule update --recursive --init
    #   cd ../../../
    # fi
    git pull
    git reset
    git clean -f
    git checkout .
    git submodule sync
    git submodule update --recursive --init
  done
  cd ${MINA_REPO_DIR}
}

buildMina() {
  cd ${MINA_REPO_DIR}
  DUNE_BUILD_COMMAND="dune build"
  if $2; then
    DUNE_BUILD_COMMAND="dune build --instrument-with bisect_ppx"
  fi
  sudo make clean
  export MINA_COMMIT_SHA1=$(git rev-parse HEAD)
  export DUNE_PROFILE="${1}"
  export RUST_TARGET_FEATURE_OPTIMISATIONS=n

  make libp2p_helper
  ${DUNE_BUILD_COMMAND} \
    src/app/cli/src/mina.exe \
    src/app/logproc/logproc.exe \
    src/app/archive/archive.exe
}

echo ""
echo "[INFO] Downloading Mina Accounts Manager from: ${MINA_ACCOUNTS_MANAGER_LINK}"
echo ""
cd ${CURRENT_DIR}
wget -O ${HOME}/accounts-manager ${MINA_ACCOUNTS_MANAGER_LINK}

echo ""
echo "[INFO] Building Archive-Node-API at path: ${ARCHIVE_NODE_API_REPO_DIR}"
echo ""
cd ${ARCHIVE_NODE_API_REPO_DIR}
rm -rf node_modules/ && npm install && npm run build
cd ${CURRENT_DIR}

for TARGET_BRANCH in "${TARGET_BRANCHES[@]}"; do
  echo ""
  echo "[INFO] Building Mina at branch: '${TARGET_BRANCH}' and then building the corresponding Docker image"
  echo ""
  BRANCH_NAME=${TARGET_BRANCH}
  # if [[ $TARGET_BRANCH == "o1js-main" ]]; then
  #   BRANCH_NAME="rampup"
  # fi

  gitPullAll && gitPullAll
  git checkout ${TARGET_BRANCH}
  rm -rf ${MINA_REPO_DIR}/src/lib/snarkyjs || true
  gitPullAll && gitPullAll
  opam switch import --switch mina --yes opam.export
  opam switch import opam.export --yes
  chmod +x scripts/pin-external-packages.sh
  ./scripts/pin-external-packages.sh
  echo ""
  echo "[INFO] For Devnet dune profile..."
  echo ""
  buildMina "devnet" false
  cd ${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}
  ./scripts/build-image.sh ${ARCH} ${MINA_REPO_DIR} ${ARCHIVE_NODE_API_REPO_DIR} full ${DOCKER_HUB_USER_NAME} ${BRANCH_NAME}-latest-devnet ${HOME}/accounts-manager
  gitPullAll && gitPullAll
  echo ""
  echo "[INFO] For Lightnet dune profile..."
  echo ""
  buildMina "lightnet" false
  cd ${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}
  ./scripts/build-image.sh ${ARCH} ${MINA_REPO_DIR} ${ARCHIVE_NODE_API_REPO_DIR} none ${DOCKER_HUB_USER_NAME} ${BRANCH_NAME}-latest-lightnet ${HOME}/accounts-manager
done

END=$(date +%s)
cd ${CURRENT_DIR}
RUNTIME=$(($(date +%s) - START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo ""
