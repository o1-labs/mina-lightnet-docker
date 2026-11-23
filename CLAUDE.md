# Mina Lightnet Docker

Docker images for lightweight Mina blockchain test networks. Provides pre-built single-node and multi-node configurations with 1000+ prefunded accounts for zkApp development and testing.

## Project Structure

```
configuration/
  Dockerfile                  # Multi-stage Docker image (base: postgres:14-bookworm)
  nginx.conf                  # NGINX reverse proxy with CORS support (port 8080)
  mina-local-network/
    daemon.json               # Genesis ledger (~1000 prefunded accounts, 1550 MINA each)
  key-pairs/                  # Key files of the prefunded accounts
scripts/
  build-all.sh                # Orchestrates multi-branch/multi-arch Docker builds
  build-image.sh              # Builds a single Docker image (uses docker buildx)
  spinup-testnet.sh           # Container entrypoint: starts PostgreSQL and NGINX, then the network with minimina
  lightnet-spec.sh            # Prints the minimina network spec from the container's env (NETWORK_TYPE, LOG_LEVEL, ...)
  test-image.sh               # Integration test: services health, transaction lifecycle, archive verification
  wait-for-network.sh         # Polls GraphQL for syncStatus: SYNCED (max 60 attempts, 10s interval)
.github/workflows/
  build-release.yml           # Manual CI: builds <version>-{devnet,lightnet} + latest-* + master-latest-* from a stable release
  build-prerelease.yml        # Manual CI: builds <version>-{devnet,lightnet} + next-* from an alpha/beta pre-release
  test.yml                    # PR CI: builds both images from the newest stable release and runs integration tests
```

## Building

```bash
# Build both images of a stable release (tags master-latest-*)
./scripts/build-all.sh --target-branches "master" --mina-release stable --mina-deb-version 4.0.4-c9e2eac

# Same, locally (skip push)
./scripts/build-all.sh --target-branches "master" --mina-release stable --mina-deb-version 4.0.4-c9e2eac --skip-push

# Key build-all.sh flags:
#   --target-branches   Mina branches (master for stable; develop/compatible only with the unused nightly type)
#   --mina-release      Release type (stable, alpha, beta; nightly is accepted but nothing is published from it)
#   --mina-deb-version  Exact deb version to install (e.g. 4.0.2-84b8d96)
#   --skip-push         Build locally, don't push to Docker Hub
#   --no-cache          Disable Docker build cache

# Build a stable release image (arm64 only for releases with Bookworm arm64 debs on stable: 4.0.4 yes, 4.0.2 no)
./scripts/build-image.sh --archs amd64,arm64 --mina-release stable --mina-deb-version 4.0.4-c9e2eac \
  --mina-profile devnet --mina-runtime-profile lightnet --proof-level none \
  --docker-user o1labs --tag 4.0.4-lightnet,latest-lightnet,master-latest-lightnet
```

Image tag format: `o1labs/mina-local-network:<mina-version>-<profile>`. Floating aliases: `latest-<profile>` and `master-latest-<profile>` = newest stable, `next-<profile>` = newest alpha/beta pre-release. `compatible-latest-<profile>` is a frozen legacy alias of 4.0.4; `develop-latest-<profile>` is a stale former nightly. No nightly images are published anymore.
Profiles: `devnet` (full proofs), `lightnet` (no proofs)

**Lightnet profile mechanics.** Only the (unused) nightly repo ships a variant deb `mina-devnet-generic-lightnet` (selected with `--mina-extra-profile lightnet`). The stable and unstable repos do not. Since Mina 4.0.2 the daemon is one network-free binary (`mina-generic`) that reads its profile from `/etc/coda/build_config/PROFILE` (or `MINA_PROFILE` env), so stable lightnet images install the devnet debs and write `lightnet` into that file (`--mina-runtime-profile lightnet`). `build-all.sh --mina-release stable` does this automatically.

## Docker Image

**Base**: `postgres:14-bookworm` | **Architectures**: amd64, arm64

### Key Build Args

| Arg | Default | Description |
|-----|---------|-------------|
| `MINA_BRANCH` | develop | Mina source branch = apt component (`stable` for the stable repo) |
| `MINA_REPO` | nightly apt repo | Debian package source |
| `MINA_PROFILE` | devnet | Deb network/profile: installs `mina-<profile>-generic` + `mina-archive-<profile>` |
| `MINA_EXTRA_PROFILE` | (empty) | Variant deb suffix, e.g. `lightnet` → `mina-devnet-generic-lightnet` (nightly only) |
| `MINA_RUNTIME_PROFILE` | (empty) | Written to `/etc/coda/build_config/PROFILE` (Mina >= 4.0.2 runtime profile) |
| `MINA_DEB_VERSION` | (empty) | Exact deb version pin (e.g. `4.0.2-84b8d96`); empty = newest in component |
| `ARCHIVE_NODE_API_VERSION` | 2.0.0 | Archive GraphQL API version (`@o1-labs/mina-archive-node-graphql`, needs Node >= 22.12) |
| `MINA_ACCOUNTS_MANAGER_VERSION` | 0.1.2 | Accounts manager version |
| `EXPLORER_VERSION` | v0.2.2 | Mina Lightweight Explorer version |
| `MINIMINA_VERSION` | 0.3.1 | minimina version, from `stable.apt.packages.minaprotocol.com` |

### Runtime Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_TYPE` | single-node | single-node or multi-node |
| `PROOF_LEVEL` | full | full or none |
| `LOG_LEVEL` | Trace | Trace/Debug/Info/Warn/Error |
| `RUN_ARCHIVE_NODE` | true | Enable archive node + PostgreSQL |
| `ARCHIVE_API_*` | see README | Archive-Node-API 2.x knobs; container defaults open CORS (`*`), introspection, GraphiQL, zkappCommands, and disable rate limiting |
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

**Multi-node**: 2 whales, 1 fish, 1 seed, 1 snark coordinator, 2 snark workers, 1 non-BP node, and the archive node's own daemon. ~4-6 min startup, ~6 GB RAM.

**minimina** ([o1-labs/minimina](https://github.com/o1-labs/minimina)) runs the network in native mode: `spinup-testnet.sh` writes the spec of `lightnet-spec.sh` to `/root/lightnet/network.toml` and runs `minimina network create` and `start` for the network `lightnet` (`/root/.minimina/lightnet`) on every start of the container. The spec's ports, the database name (`POSTGRES_DB`) and the log paths zkapp-cli reads (symlinks into `/root/.minimina/lightnet/logs`) are those of the former `mina-local-network.sh`. Block producer and libp2p keys come from the seed `lightnet`, so they are the same on every start. minimina also runs Archive-Node-API and the accounts manager (the image's own builds, `bin` in the spec).

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
./scripts/build-image.sh --archs amd64 --mina-release stable --mina-deb-version 4.0.4-c9e2eac \
  --mina-profile devnet --mina-runtime-profile lightnet --proof-level none \
  --archive-api-version 2.0.0 --docker-user test-local --tag 4.0.4-lightnet --skip-push
./scripts/test-image.sh test-local/mina-local-network:4.0.4-lightnet
```

CI runs automatically on PRs to develop via `.github/workflows/test.yml`.

The integration test (`scripts/test-image.sh`) verifies: daemon sync, accounts manager, archive API, PostgreSQL, and a full transaction lifecycle (send payment + verify in archive).

## Important Gotchas

- **The daemon's wallet is empty at start.** To send transactions, import a key file into the daemon via `importAccount` GraphQL mutation, or acquire the account with `?unlockAccount=true`: the accounts manager imports its key file (from `/root/lightnet/key-pairs`).
- **Key file permissions.** The Mina daemon requires `0700` on the directory and `0600` on the key file. Use `docker cp` + `chmod` when importing keys at runtime.
- **NGINX proxy (port 8080) forwards to the daemon's REST port (3101 in single-node).** The daemon's actual REST port is base port + 1 (3100 + 1 = 3101). GraphQL mutations like `unlockAccount` work through this proxy.
- **Genesis ledger accounts.** `daemon.json` contains ~1007 accounts. 1000 have `sk` populated; 7 infrastructure accounts (online/offline whales, fish, snark coordinator) of the former `mina-local-network.sh` have `sk: null`. The image's genesis ledger (`/root/lightnet/accounts.json`) has only the 1000; minimina adds its block producers (11,550,000 MINA each, fish 65,500).
- **Key-pairs directory** contains 1003 encrypted wallet files (JSON format with `xsalsa20poly1305` encryption). Password for all keys: `naughty blue worm`.
- **minimina makes the archive database.** The postgres entrypoint starts with `POSTGRES_DB=postgres`; minimina creates the `POSTGRES_DB` database (default `archive`) with its schema, and refuses to drop a database it did not create.
- **minimina comes from the signed stable repo** for amd64 and arm64 (arm64 since 0.3.1), so it installs in both images of a release.
- **Stable repo architectures:** 4.0.2 and older are amd64 only. 4.0.4 also has Bookworm arm64 `mina-devnet-generic`, `mina-archive-devnet`, `mina-logproc` (and their dependencies), published by the separate arm64 release pipeline in MinaProtocol/mina. Stable has no `mina-devnet-generic-lightnet`. Use `--mina-runtime-profile lightnet` (writes the PROFILE hint) instead of `--mina-extra-profile`. The 4.0.2 debs are tent metapackages: `mina-devnet-generic` → `mina-generic` + `mina-devnet-profile`; `mina-archive-devnet` → `mina-archive-generic` + `mina-devnet-profile`.

## Key Conventions

- Key directories: permissions 0700; key files: 0600
- Genesis ledger config: `configuration/mina-local-network/daemon.json`
- Container entrypoint: `scripts/spinup-testnet.sh`
- Transaction finality (k): 30 blocks; slots per epoch: 720
- CI pushes to Docker Hub as `o1labs/mina-local-network`
- Shell scripts use `bash` with `set -euo pipefail`
