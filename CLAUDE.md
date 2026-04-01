# Mina Lightnet Docker

Docker images for lightweight Mina blockchain test networks. Provides pre-built single-node and multi-node configurations with 1000+ prefunded accounts for zkApp development and testing.

## Project Structure

```
configuration/
  Dockerfile                  # Multi-stage Docker image (base: postgres:14-bookworm)
  nginx.conf                  # NGINX reverse proxy with CORS support (port 8080)
  mina-local-network/
    daemon.json               # Genesis ledger (~1000 prefunded accounts, 1550 MINA each)
    libp2p_keys/              # LibP2P peer identity keys
    nodes/                    # Per-node configs (whale_0, whale_1, fish_0, seed, snark_coordinator, snark_workers, node_0, archive)
    key-pairs/                # Pre-generated key pairs
    offline_*_keys/           # Offline wallet keys
    online_*_keys/            # Online (hot) wallet keys
scripts/
  build-all.sh                # Orchestrates multi-branch/multi-arch Docker builds
  build-image.sh              # Builds a single Docker image (uses docker buildx)
  spinup-testnet.sh           # Container entrypoint: starts PostgreSQL, Archive API, Accounts Manager, Mina daemons, NGINX
  test-image.sh               # Integration test: services health, transaction lifecycle, archive verification
  wait-for-network.sh         # Polls GraphQL for syncStatus: SYNCED (max 60 attempts, 10s interval)
.github/workflows/
  build.yml                   # Manual-dispatch CI: builds nightly images for develop/compatible/master
  test.yml                    # PR CI: builds image and runs integration tests
```

## Building

```bash
# Build all images (nightly, multi-arch)
./scripts/build-all.sh --target-branches "develop" --mina-release nightly

# Build single image locally (skip push)
./scripts/build-all.sh --target-branches "develop" --mina-release nightly --skip-push

# Key build-all.sh flags:
#   --target-branches   Mina branches (develop, compatible, master)
#   --mina-release      Release type (nightly, alpha, beta)
#   --skip-push         Build locally, don't push to Docker Hub
#   --no-cache          Disable Docker build cache
```

Image tag format: `o1labs/mina-local-network:<branch>-latest-<profile>[-suffix]`
Profiles: `devnet` (full proofs), `lightnet` (no proofs)

## Docker Image

**Base**: `postgres:14-bookworm` | **Architectures**: amd64, arm64

### Key Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `MINA_BRANCH` | develop | Mina source branch |
| `MINA_REPO` | nightly apt repo | Debian package source |
| `MINA_PROFILE` | devnet | devnet or lightnet |
| `ARCHIVE_NODE_API_VERSION` | 0.0.8 | Archive GraphQL API version |
| `MINA_ACCOUNTS_MANAGER_VERSION` | 0.1.1 | Accounts manager version |
| `EXPLORER_VERSION` | v0.2.2 | Mina Lightweight Explorer version |

### Runtime Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_TYPE` | single-node | single-node or multi-node |
| `PROOF_LEVEL` | full | full or none |
| `LOG_LEVEL` | Trace | Trace/Debug/Info/Warn/Error |
| `RUN_ARCHIVE_NODE` | true | Enable archive node + PostgreSQL |
| `SLOT_TIME` | 20000 | Block slot time in ms |

### Exposed Ports

- **3085** — Mina GraphQL (single-node)
- **4001, 4006** — Whale GraphQL (multi-node)
- **5001** — Fish GraphQL (multi-node)
- **5432** — PostgreSQL
- **8080** — NGINX reverse proxy
- **8181** — Mina Accounts Manager
- **8282** — Archive Node API

## Network Configurations

**Single-node**: One daemon as block producer + snark worker. ~1-2 min startup, ~900 MB RAM.

**Multi-node**: 2 whales, 1 fish, 1 seed, 1 snark coordinator, 1 snark worker, 1 non-BP node. ~4-6 min startup, ~6 GB RAM.

## Services & APIs

- **Mina GraphQL** (port 3085): Blockchain queries and transaction submission
- **Accounts Manager** (port 8181): `GET /acquire-account`, `PUT /release-account`, `GET /list-acquired-accounts`, `PUT /lock-account`, `PUT /unlock-account`
- **Archive Node API** (port 8282): GraphQL API for historical blockchain data
- **NGINX** (port 8080): CORS-enabled reverse proxy to Mina GraphQL + Lightweight Explorer UI
- **Lightweight Explorer** (port 8080, path /): Web-based block explorer for inspecting blocks, accounts, transactions, and mempool. Source: [mina-lightweight-explorer](https://github.com/o1-labs/mina-lightweight-explorer)

## Mina Debian Repositories

- `nightly.apt.packages.minaprotocol.com` — Nightly builds (signed)
- `unstable.apt.packages.minaprotocol.com` — Alpha/beta (signed)
- `stable.apt.packages.minaprotocol.com` — Stable releases (signed)
- `packages.o1test.net` — Unsigned, multichannel (legacy)

## Testing

```bash
# Build and run integration tests locally (builds image then runs test suite)
./scripts/build-all.sh --target-branches "develop" --mina-release nightly --docker-hub-user test-local --skip-push
./scripts/test-image.sh test-local/mina-local-network:develop-latest-lightnet
```

CI runs automatically on PRs to develop via `.github/workflows/test.yml`.

The integration test (`scripts/test-image.sh`) verifies: daemon sync, accounts manager, archive API, PostgreSQL, and a full transaction lifecycle (send payment + verify in archive).

## Important Gotchas

- **Wallet store is empty in the container.** Although `build-all.sh` copies key-pairs into a temp folder during build, the Docker build context is the repo root, so `configuration/mina-local-network/nodes/*/wallets/store/` directories in the image are empty. To send transactions, you must import a key file into the daemon via `importAccount` GraphQL mutation.
- **Key file permissions.** The Mina daemon requires `0700` on the directory and `0600` on the key file. Use `docker cp` + `chmod` when importing keys at runtime.
- **Accounts Manager does not auto-import keys.** `/acquire-account` returns `{pk, sk}` from the genesis ledger but does NOT import the key into the daemon's wallet. The `?unlockAccount=true` parameter only works if the key is already in the daemon's wallet store.
- **NGINX proxy (port 8080) forwards to the daemon's REST port (3101 in single-node).** The daemon's actual REST port is base port + 1 (3100 + 1 = 3101). GraphQL mutations like `unlockAccount` work through this proxy.
- **Genesis ledger accounts.** `daemon.json` contains ~1007 accounts. 1000 have `sk` populated; 7 infrastructure accounts (online/offline whales, fish, snark coordinator) have `sk: null`.
- **Key-pairs directory** contains 1003 encrypted wallet files (JSON format with `xsalsa20poly1305` encryption). Password for all keys: `naughty blue worm`.
- **mina-local-network.sh** is downloaded from the Mina repo at a pinned commit (`MINA_COMMIT` in Dockerfile). It is NOT part of this repo. In `--demo` mode with `--config inherit`, it preserves pre-existing config at `~/.mina-network/` and runs a single seed node.

## Key Conventions

- Key directories: permissions 0700; key files: 0600
- Genesis ledger config: `configuration/mina-local-network/daemon.json`
- Container entrypoint: `scripts/spinup-testnet.sh`
- Transaction finality (k): 30 blocks; slots per epoch: 720
- CI pushes to Docker Hub as `o1labs/mina-local-network`
- Shell scripts use `bash` with `set -euo pipefail`
