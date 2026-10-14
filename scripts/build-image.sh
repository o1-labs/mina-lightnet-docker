#!/usr/bin/env bash

set -euo pipefail

# Default values
ARCHS=""
MINA_RELEASE="stable"
MINA_BRANCH=""
ARCHIVE_NODE_API_VERSION="2.0.0"
PROOF_LEVEL="full"
DOCKER_HUB_USER_NAME=""
DOCKER_HUB_IMAGE_TAG=""
ACCOUNTS_MANAGER_VERSION="0.1.2"
MINA_PROFILE="devnet"
MINA_EXTRA_PROFILE=""
MINA_RUNTIME_PROFILE=""
MINA_DEB_VERSION=""
EXPLORER_VERSION="v0.2.2"
PUSH=1
NO_CACHE=0

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -a, --archs ARCHS                     Architecture (required)"
  echo "  -m, --mina-release VERSION            Mina release: nightly, alpha, beta, stable (required)"
  echo "  -b, --mina-branch BRANCH              Mina branch = apt component (nightly only; alpha/beta/stable set it)"
  echo "      --mina-deb-version VERSION         Exact mina deb version to install, e.g. 4.0.2-84b8d96 (optional)"
  echo "  -n, --archive-api-version PATH        Archive-Node-API version (required)"
  echo "  -p, --proof-level LEVEL               Proof level (required)"
  echo "  -u, --docker-user USER                Docker Hub user name (required)"
  echo "  -t, --tag TAG[,TAG...]                Docker Hub image tag(s), comma-separated (required)"
  echo "      --mina-profile PROFILE            Mina profile = deb network (optional, default: devnet)"
  echo "      --mina-extra-profile EXTRA_PROFILE Extra Mina profile; installs the mina-<profile>-generic-<extra> variant deb (nightly only)"
  echo "      --mina-runtime-profile PROFILE    Runtime profile written to /etc/coda/build_config/PROFILE (Mina >= 4.0.2; e.g. lightnet)"
  echo "  -c, --accounts-manager-version PATH   Accounts-Manager version (optional)"
  echo "      --explorer-version VERSION         Lightweight Explorer version (optional, default: v0.2.2)"
  echo "  -s, --skip-push                       Skip pushing the image to Docker Hub (optional, default: false)"
  echo "      --no-cache                        Disable Docker build cache (optional, default: false)"
  echo "  -h, --help                            Display this help message"
  echo ""
  echo "Example:"
  echo "  $0 --archs amd64 --mina-release stable --mina-deb-version 4.0.2-84b8d96 --mina-runtime-profile lightnet --proof-level none --docker-user myuser --tag 4.0.2-lightnet"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--archs)
      ARCHS="$2"
      shift 2
      ;;
    -m|--mina-release)
      MINA_RELEASE="$2"
      shift 2
      ;;
    -b|--mina-branch)
      MINA_BRANCH="$2"
      shift 2
      ;;
    -n|--archive-api-version)
      ARCHIVE_NODE_API_VERSION="$2"
      shift 2
      ;;
    --mina-profile)
      MINA_PROFILE="$2"
      shift 2
      ;;
    --mina-extra-profile)
      MINA_EXTRA_PROFILE="$2"
      shift 2
      ;;
    --mina-runtime-profile)
      MINA_RUNTIME_PROFILE="$2"
      shift 2
      ;;
    --mina-deb-version)
      MINA_DEB_VERSION="$2"
      shift 2
      ;;
    -p|--proof-level)
      PROOF_LEVEL="$2"
      shift 2
      ;;
    -u|--docker-user)
      DOCKER_HUB_USER_NAME="$2"
      shift 2
      ;;
    -t|--tag)
      DOCKER_HUB_IMAGE_TAG="$2"
      shift 2
      ;;
    -c|--accounts-manager-version)
      ACCOUNTS_MANAGER_VERSION="$2"
      shift 2
      ;;
    --explorer-version)
      EXPLORER_VERSION="$2"
      shift 2
      ;;
    -s|--skip-push)
      PUSH=0
      shift 1
      ;;
    --no-cache)
      NO_CACHE=1
      shift 1
      ;;
    -h|--help)
      usage
      ;;
    *)
      echo "Unknown option: $1"
      usage
      ;;
  esac
done

# Validate required parameters
if [[ -z "$ARCHS" ]]; then
  echo "Error: Architectures (-a/--archs) are required"
  usage
  exit 1
fi

if [[ -z "$MINA_RELEASE" ]]; then
  echo "Error: Mina release (-m/--mina-release) is required"
  usage
  exit 1
fi

if [[ -z "$ARCHIVE_NODE_API_VERSION" ]]; then
  echo "Error: Archive Node API version (-n/--archive-api-version) is required"
  usage
  exit 1
fi

if [[ -z "$PROOF_LEVEL" ]]; then
  echo "Error: Proof level (-p/--proof-level) is required"
  usage
  exit 1
fi

if [[ -z "$DOCKER_HUB_USER_NAME" ]]; then
  echo "Error: Docker Hub user name (-u/--docker-user) is required"
  usage
  exit 1
fi

if [[ -z "$DOCKER_HUB_IMAGE_TAG" ]]; then
  echo "Error: Docker Hub image tag (-t/--tag) is required"
  usage
  exit 1
fi

START=$(date +%s)

case $MINA_RELEASE in
  "nightly")
    echo "Using NIGHTLY Mina release."
    MINA_REPO="https://nightly.apt.packages.minaprotocol.com"
    ;;
  "alpha")
    echo "Using ALPHA Mina release."
    MINA_REPO="https://unstable.apt.packages.minaprotocol.com"
    MINA_BRANCH="alpha"
    ;;
  "beta")
    echo "Using BETA Mina release."
    MINA_REPO="https://unstable.apt.packages.minaprotocol.com"
    MINA_BRANCH="beta"
    ;;
  "stable")
    echo "Using STABLE Mina release."
    MINA_REPO="https://stable.apt.packages.minaprotocol.com"
    MINA_BRANCH="stable"
    ;;
  *)
    echo "Error: Unsupported MINA_RELEASE value: $MINA_RELEASE. Supported values are: nightly, alpha, beta, stable."
    exit 1
    ;;
esac

# Convert ARCHS to platform format (linux/{arch})
PLATFORMS=""
IFS=',' read -ra ARCH_ARRAY <<< "$ARCHS"
for arch in "${ARCH_ARRAY[@]}"; do
  if [[ -z "$PLATFORMS" ]]; then
    PLATFORMS="linux/${arch}"
  else
    PLATFORMS="${PLATFORMS},linux/${arch}"
  fi
done

echo ""
echo "Building the Docker image..."
echo ""

# Image references (one per comma-separated tag)
TAG_ARGS=()
IFS=',' read -ra TAG_ARRAY <<< "$DOCKER_HUB_IMAGE_TAG"
for tag in "${TAG_ARRAY[@]}"; do
  docker rmi -f "${DOCKER_HUB_USER_NAME}/mina-local-network:${tag}" || true
  TAG_ARGS+=(-t "${DOCKER_HUB_USER_NAME}/mina-local-network:${tag}")
done
docker rmi -f mina-local-network || true

BUILD_ARGS=(
  "--build-arg=MINA_PROFILE=${MINA_PROFILE}"
  "--build-arg=MINA_REPO=${MINA_REPO}"
  "--build-arg=MINA_BRANCH=${MINA_BRANCH}"
  "--build-arg=ARCHIVE_NODE_API_VERSION=${ARCHIVE_NODE_API_VERSION}"
  "--build-arg=MINA_ACCOUNTS_MANAGER_VERSION=${ACCOUNTS_MANAGER_VERSION}"
  "--build-arg=PROOF_LEVEL=${PROOF_LEVEL}"
  "--build-arg=EXPLORER_VERSION=${EXPLORER_VERSION}"
)
if [[ -n "$MINA_EXTRA_PROFILE" ]]; then
  BUILD_ARGS+=("--build-arg=MINA_EXTRA_PROFILE=${MINA_EXTRA_PROFILE}")
fi
if [[ -n "$MINA_RUNTIME_PROFILE" ]]; then
  BUILD_ARGS+=("--build-arg=MINA_RUNTIME_PROFILE=${MINA_RUNTIME_PROFILE}")
fi
if [[ -n "$MINA_DEB_VERSION" ]]; then
  BUILD_ARGS+=("--build-arg=MINA_DEB_VERSION=${MINA_DEB_VERSION}")
fi
if [[ $NO_CACHE -eq 1 ]]; then
  BUILD_ARGS+=(--no-cache)
fi

if [[ $PUSH -eq 1 ]]; then
  echo ""
  echo "Publishing the Docker image..."
  echo ""
  docker buildx build --platform "${PLATFORMS}" --push "${TAG_ARGS[@]}" "${BUILD_ARGS[@]}" . -f configuration/Dockerfile
else
  echo ""
  echo "Skipping the Docker image publishing step as requested."
  echo ""

  # Detect current architecture
  CURRENT_ARCH=$(uname -m)
  case "$CURRENT_ARCH" in
    x86_64)
      DETECTED_ARCH="amd64"
      ;;
    aarch64|arm64)
      DETECTED_ARCH="arm64"
      ;;
    *)
      echo "Warning: Unknown architecture $CURRENT_ARCH, defaulting to amd64"
      DETECTED_ARCH="amd64"
      ;;
  esac

  echo "Detected architecture: $DETECTED_ARCH (system: $CURRENT_ARCH)"
  echo "Building only for current architecture to enable local loading..."
  echo ""

  docker buildx build --platform "linux/${DETECTED_ARCH}" --load "${TAG_ARGS[@]}" "${BUILD_ARGS[@]}" . -f configuration/Dockerfile
fi

END=$(date +%s)
RUNTIME=$((END-START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo "[INFO] Docker Hub link: https://hub.docker.com/r/${DOCKER_HUB_USER_NAME}/mina-local-network/tags"
echo ""
