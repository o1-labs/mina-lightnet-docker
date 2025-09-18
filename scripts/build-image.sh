#!/usr/bin/env bash

set -euo pipefail

# Default values
ARCH=""
MINA_RELEASE="stable"
MINA_BRANCH=""
ARCHIVE_NODE_API_VERSION="1.0.0"
PROOF_LEVEL="full"
DOCKER_HUB_USER_NAME=""
DOCKER_HUB_IMAGE_TAG=""
ACCOUNTS_MANAGER_VERSION="v1.0.0"
PUSH=1

# Function to display usage
usage() {
  echo "Usage: $0 [OPTIONS]"
  echo ""
  echo "Options:"
  echo "  -a, --arch ARCH                       Architecture (required)"
  echo "  -m, --mina-release VERSION            Mina release (required)"
  echo "  -b, --mina-branch BRANCH              Mina branch (optional)"
  echo "  -n, --archive-api-version PATH        Archive-Node-API version (required)"
  echo "  -p, --proof-level LEVEL               Proof level (required)"
  echo "  -u, --docker-user USER                Docker Hub user name (required)"
  echo "  -t, --tag TAG                         Docker Hub image tag (required)"
  echo "  -c, --accounts-manager-version PATH   Accounts-Manager version (optional)"
  echo "  -s, --skip-push                       Skip pushing the image to Docker Hub (optional, default: false)"
  echo "  -h, --help                            Display this help message"
  echo ""
  echo "Example:"
  echo "  $0 --arch amd64 --mina-version 3.3.0*  --archive-api-version v1.0.0 --proof-level full --accounts-manager-version 1.0.0 --docker-user myuser --tag latest"
}

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    -a|--arch)
      ARCH="$2"
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
    -s|--skip-push)
      PUSH=0
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
if [[ -z "$ARCH" ]]; then
  echo "Error: Architecture (-a/--arch) is required"
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
  "stable")
    echo "Using STABLE Mina release."
    MINA_REPO="https://stable.apt.packages.minaprotocol.com"
    MINA_BRANCH="stable"
    ;;
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
  *)
    echo "Error: Unsupported MINA_RELEASE value: $MINA_RELEASE. Supported values are: STABLE, NIGHTLY."
    exit 1
    ;;
esac

echo ""
echo "Building the Docker image..."
echo ""
docker rmi -f ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH} || true
docker rmi -f mina-local-network || true
docker build --platform linux/${ARCH} -t mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH} --build-arg="MINA_PROFILE=${MINA_PROFILE}" --build-arg="MINA_REPO=${MINA_REPO}" --build-arg="MINA_BRANCH=${MINA_BRANCH}" --build-arg="ARCHIVE_NODE_API_TAG=${ARCHIVE_NODE_API_VERSION}" --build-arg="MINA_ACCOUNTS_MANAGER_VERSION=${ACCOUNTS_MANAGER_VERSION}" --build-arg="PROOF_LEVEL=${PROOF_LEVEL}" . -f configuration/Dockerfile


if [[ $PUSH -eq 1 ]]; then
  echo ""
  echo "Publishing the Docker image..."
  docker tag mina-local-network ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH}
  docker push ${DOCKER_HUB_USER_NAME}/mina-local-network:${DOCKER_HUB_IMAGE_TAG}-${ARCH}

else
  echo ""
  echo "Skipping the Docker image publishing step as requested."
  echo ""
  exit 0
fi

END=$(date +%s)
RUNTIME=$((END-START))

echo ""
echo "[INFO] Done. Runtime: ${RUNTIME} seconds"
echo "[INFO] Docker Hub link: https://hub.docker.com/r/${DOCKER_HUB_USER_NAME}/mina-local-network/tags"
echo ""
