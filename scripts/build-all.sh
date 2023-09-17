#!/usr/bin/env bash
# set -x
# Exit script when commands fail
# set -e

if [[ $# -lt 5 ]]; then
  echo "Usage: $0 <Mina repository root path> <Docker image building scripts repository root path> <Mina-Accounts-Manager repository root path> <Docker Hub user name> <Target branches>"
  exit 1
fi

# https://community.hetzner.com/tutorials/resize-ext-partition

START=$(date +%s)
CURRENT_DIR="$(pwd)"

MINA_REPO_DIR=${1}
DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR=${2}
MINA_ACCOUNTS_MANAGER_REPO_DIR=${3}
DOCKER_HUB_USER_NAME=${4}
TARGET_BRANCHES=(${5})

cd ${MINA_REPO_DIR}
cd ../
GIT_PULL_ALL_DIR=$(pwd)
cd ${CURRENT_DIR}

gitPullAll() {
  for DIR in $(find ${GIT_PULL_ALL_DIR} -maxdepth 1 -mindepth 1 -type d); do
    cd ${DIR}
    echo ""
    echo "Updating the \"$(pwd)\" repo:"
    if [[ ${DIR} == *"mina" ]]; then
      # TODO: Update after submodule will be changed to "o1js"
      cd src/lib/snarkyjs/src/bindings
      git stash
      cd ../../../../../
      cd src/lib/snarkyjs
      git stash
      git submodule sync
      git submodule update --recursive --init
      cd ../../../
    fi
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
  MINA_COMMIT_SHA1=$(git rev-parse HEAD) \
  DUNE_PROFILE="${1}" \
    ${DUNE_BUILD_COMMAND} \
    src/app/cli/src/mina.exe \
    src/app/logproc/logproc.exe \
    src/app/archive/archive.exe
  make libp2p_helper
}

echo ""
echo "[INFO] Building Mina Accounts Manager at path: ${MINA_ACCOUNTS_MANAGER_REPO_DIR}"
echo ""
cd ${MINA_ACCOUNTS_MANAGER_REPO_DIR}
git stash && git pull && git reset && git clean -f && git checkout . && git submodule sync && git submodule update --recursive --init
./gradlew nativeCompile
cd ${CURRENT_DIR}

for TARGET_BRANCH in "${TARGET_BRANCHES[@]}"; do
  echo ""
  echo "[INFO] Building Mina at branch: '${TARGET_BRANCH}' and then the corresponding Docker Image"
  echo ""
  BRANCH_NAME=${TARGET_BRANCH}
  if [[ $TARGET_BRANCH == "rampup-before-accidental-merge" ]]; then
    BRANCH_NAME="rampup"
  fi

  gitPullAll && gitPullAll
  git checkout ${TARGET_BRANCH}
  gitPullAll && gitPullAll
  opam switch import --switch mina --yes opam.export
  chmod +x scripts/pin-external-packages.sh
  ./scripts/pin-external-packages.sh
  echo ""
  echo "[INFO] For Devnet dune profile..."
  echo ""
  buildMina "devnet" false
  cd ${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}
  ./scripts/build-image.sh ${HOME}/projects/o1labs/mina full ${DOCKER_HUB_USER_NAME} ${BRANCH_NAME}-latest-devnet ${MINA_ACCOUNTS_MANAGER_REPO_DIR}/build/native/nativeCompile/accounts-manager
  gitPullAll && gitPullAll
  echo ""
  echo "[INFO] For Lightnet dune profile..."
  echo ""
  buildMina "lightnet" false
  cd ${DOCKER_IMAGE_BUILDING_SCRIPTS_REPO_DIR}
  ./scripts/build-image.sh ${HOME}/projects/o1labs/mina none ${DOCKER_HUB_USER_NAME} ${BRANCH_NAME}-latest-lightnet ${MINA_ACCOUNTS_MANAGER_REPO_DIR}/build/native/nativeCompile/accounts-manager
done

END=$(date +%s)
cd ${CURRENT_DIR}
RUNTIME=$(($(date +%s) - START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo ""
