# Lightweight Mina Network Docker Images

Spin up a lightweight Mina network within a single container.

These Docker images provide a simple and efficient way to deploy and run lightweight Mina blockchain networks for testing purposes. It is an implementation of the [Dockerization of Mina local networks](https://github.com/o1-labs/rfcs/blob/main/0004-dockerised-local-network.md) RFC.

Each Docker image is packaged with a genesis ledger configuration containing more than 1000 prefunded accounts. Each account has a balance of 1550 MINA.

## Table of Contents

- [Related Projects](#related-projects)
- [Related Documentation](#related-documentation)
- [Quick Start](#quick-start)
- [Specifications](#specifications)
- [Environment Variables](#environment-variables)
- [Network Types](#network-types)
  - [Single Node](#single-node)
  - [Multi-Node](#multi-node)
- [Connecting to the Network](#connecting-to-the-network)
- [Mina Accounts Manager](#mina-accounts-manager)
- [Image Tags](#image-tags)
- [Building Images](#building-images)

## Related Projects

- [Mina protocol](https://github.com/MinaProtocol/mina)
- [o1js](https://github.com/o1-labs/o1js)
- [zkapp-cli](https://github.com/o1-labs/zkapp-cli)
- [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API)
- [Wait for Mina network GitHub action](https://github.com/o1-labs/wait-for-mina-network-action)
- [Mina accounts manager](https://github.com/shimkiv/mina-accounts-manager)
- [Mina lightweight explorer](https://github.com/o1-labs/mina-lightweight-explorer)

## Related Documentation

- [Testing zkApps with Lightnet](https://docs.minaprotocol.com/zkapps/testing-zkapps-lightnet)

## Quick Start

```shell
docker run --rm --pull=always -it \
  --env NETWORK_TYPE="single-node" \
  --env PROOF_LEVEL="none" \
  -p 3085:3085 \
  -p 5432:5432 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8282:8282 \
  o1labs/mina-local-network:compatible-latest-lightnet
```

Wait for the network to synchronize (1-2 minutes for single-node), then connect your application to `http://127.0.0.1:8080/graphql`.

## Specifications

- This Docker image exposes port `8080` served by the NGINX reverse proxy with proper cross-origin resource sharing (CORS) management, which passes requests to an available Mina Daemon GraphQL endpoint.
- To ensure that **o1js** zkApps applications work without additional environment configuration, use an endpoint like `http://127.0.0.1:8080/graphql` to communicate with the Mina GraphQL endpoint.
- By default, containers run the [Mina Archive Node](https://docs.minaprotocol.com/node-operators/archive-node) along with the PostgreSQL RDBMS that stores the blockchain data.

## Environment Variables

Configure the container behavior using these environment variables:

| Variable | Default | Description |
|----------|---------|-------------|
| `NETWORK_TYPE` | `single-node` | Network topology type. Options: `single-node` (lightweight, fast startup) or `multi-node` (more realistic network simulation with multiple nodes) |
| `PROOF_LEVEL` | `full` | Cryptographic proof level. Options: `full` (generate real proofs, slower), `none` (skip proof generation, faster for testing) |
| `LOG_LEVEL` | `Trace` | Logging verbosity. Options: `Trace`, `Debug`, `Info`, `Warn`, `Error` |
| `RUN_ARCHIVE_NODE` | `true` | Run Archive Node and PostgreSQL. Set to `false` to disable archive functionality and reduce resource usage |
| `SLOT_TIME` | `20000` | Block slot time in milliseconds. Lower values produce blocks faster but may increase resource consumption |
| `POSTGRES_USER` | `postgres` | PostgreSQL username for archive database |
| `POSTGRES_PASSWORD` | `postgres` | PostgreSQL password for archive database |
| `POSTGRES_DB` | `archive` | PostgreSQL database name for archive data |

### Example with Custom Configuration

```shell
docker run --rm --pull=always -it \
  --env NETWORK_TYPE="single-node" \
  --env PROOF_LEVEL="none" \
  --env LOG_LEVEL="Info" \
  --env RUN_ARCHIVE_NODE="true" \
  --env SLOT_TIME="20000" \
  -p 3085:3085 \
  -p 5432:5432 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8282:8282 \
  o1labs/mina-local-network:compatible-latest-lightnet
```

### Disabling Archive Node

To prevent the Mina Archive Node and RDBMS from running (reduces memory usage):

```shell
docker run ... --env RUN_ARCHIVE_NODE="false" ...
```

Note: When Archive Node is disabled, [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API) won't be available.

## Network Types

### Single Node

A lightweight configuration running a single Mina Daemon that acts as block producer, snark worker, and seed node simultaneously.

```shell
docker run --rm --pull=always -it \
  --env NETWORK_TYPE="single-node" \
  --env PROOF_LEVEL="none" \
  --env LOG_LEVEL="Info" \
  --env RUN_ARCHIVE_NODE="true" \
  --env SLOT_TIME="20000" \
  -p 3085:3085 \
  -p 5432:5432 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8282:8282 \
  o1labs/mina-local-network:compatible-latest-lightnet
```

#### Single Node Network Properties

| Property | Value |
|----------|-------|
| Transaction finality (k) | 30 blocks |
| Slots per epoch | 720 |
| Block production | ~20-40 seconds |
| Transactions per block | 5-8 |
| RAM consumption | ~850-970 MB (after initial spike, if running < 2 hours) |
| Startup/sync time | ~1-2 minutes |

#### Single Node Exposed Ports

| Port | Service |
|------|---------|
| `3085` | Mina Daemon GraphQL endpoint |
| `5432` | PostgreSQL RDBMS |
| `8080` | NGINX reverse proxy (recommended endpoint) |
| `8181` | Mina Accounts Manager |
| `8282` | Archive-Node-API |

#### Single Node Services Topology

```
+-------------------+   +-------------------+
|                   |   |                   |
|  Mina             |   |  NGINX            |
|  multi-purpose    |   |  Reverse Proxy    |
|  Daemon           |   |                   |
|                   |   |                   |
+-------------------+   +-------------------+

+-------------------+   +-------------------+
|                   |   |                   |
|  PostgreSQL       |   |  Mina Accounts    |
|  RDBMS (optional) |   |  Manager          |
|                   |   |                   |
+-------------------+   +-------------------+

+-------------------+   +-------------------+
|                   |   |                   |
|  Archive-Node-API |   |  Mina Archive     |
|  (optional)       |   |  Node (optional)  |
|                   |   |                   |
+-------------------+   +-------------------+
```

### Multi-Node

A more realistic network simulation with multiple independent Mina Daemon processes including seed nodes, block producers (whales and fish), snark coordinator, and snark worker.

```shell
docker run --rm --pull=always -it \
 --env NETWORK_TYPE="multi-node" \
 --env PROOF_LEVEL="none" \
 --env LOG_LEVEL="Info" \
 --env RUN_ARCHIVE_NODE="true" \
 --env SLOT_TIME="20000" \
 -p 4001:4001 \
 -p 4006:4006 \
 -p 5001:5001 \
 -p 5432:5432 \
 -p 6001:6001 \
 -p 8080:8080 \
 -p 8181:8181 \
 -p 8282:8282 \
 o1labs/mina-local-network:compatible-latest-lightnet
```

#### Multi-Node Network Properties

| Property | Value |
|----------|-------|
| Transaction finality (k) | 30 blocks |
| Slots per epoch | 720 |
| Block production | ~20-40 seconds |
| Transactions per block | 5-8 |
| RAM consumption | ~5.5-6+ GB |
| Startup/sync time | ~4-6 minutes |

#### Multi-Node Exposed Ports

| Port | Service |
|------|---------|
| `4001` | Whale #1 Mina Daemon GraphQL endpoint |
| `4006` | Whale #2 Mina Daemon GraphQL endpoint |
| `5001` | Fish #1 Mina Daemon GraphQL endpoint |
| `5432` | PostgreSQL RDBMS |
| `6001` | Non block-producing node #1 GraphQL endpoint |
| `8080` | NGINX reverse proxy (routes to Whale #2) |
| `8181` | Mina Accounts Manager |
| `8282` | Archive-Node-API |

#### Multi-Node Services Topology

```
+-------------------+   +-------------------+
|                   |   |                   |
|  NGINX            |   |  Mina             |
|  Reverse Proxy    |   |  Seed node 1      |
|                   |   |                   |
+-------------------+   +-------------------+

+-------------------+   +-------------------+   +-------------------+
|                   |   |                   |   |                   |
|  Mina             |   |  Mina             |   |  Mina             |
|  Block producer   |   |  Block producer   |   |  Block producer   |
|  Whale 1          |   |  Whale 2          |   |  Fish 1           |
|                   |   |                   |   |                   |
+-------------------+   +-------------------+   +-------------------+

+-------------------+   +--------------------+   +-------------------+
|                   |   |                    |   |                   |
|  Mina             |   |  Mina              |   |  Mina             |
|  Non BP           |   |  Snark coordinator |   |  Snark worker     |
|  Node 1           |   |                    |   |                   |
|                   |   |                    |   |                   |
+-------------------+   +--------------------+   +-------------------+

+-------------------+   +-------------------+
|                   |   |                   |
|  PostgreSQL       |   |  Mina Accounts    |
|  RDBMS (optional) |   |  Manager          |
|                   |   |                   |
+-------------------+   +-------------------+

+-------------------+   +-------------------+
|                   |   |                   |
|  Archive-Node-API |   |  Mina Archive     |
|  (optional)       |   |  Node (optional)  |
|                   |   |                   |
+-------------------+   +-------------------+
```

## Connecting to the Network

### GraphQL Endpoint

Connect your application to the Mina network using the GraphQL endpoint:

```
http://127.0.0.1:8080/graphql
```

This endpoint goes through NGINX reverse proxy with proper CORS headers, making it compatible with browser-based applications.

### PostgreSQL Database

Connect to the archive database for querying historical blockchain data:

```
postgresql://postgres:postgres@127.0.0.1:5432/archive
```

### Using with o1js

```javascript
import { Mina } from 'o1js';

const network = Mina.Network('http://127.0.0.1:8080/graphql');
Mina.setActiveInstance(network);
```

### Waiting for Network Readiness

The network needs to reach a synchronized state before it can process transactions. You can poll the GraphQL endpoint or use the [wait-for-mina-network](https://github.com/marketplace/actions/wait-for-mina-network) GitHub Action in CI/CD pipelines.

Example health check:

```shell
curl -s http://127.0.0.1:8080/graphql \
  -H 'Content-Type: application/json' \
  -d '{"query": "{ syncStatus }"}' | jq -r '.data.syncStatus'
```

Wait until the response is `SYNCED`.

### Logs

Logs are stored inside the container at:

```shell
# Single-node
/root/logs/*.log

# Multi-node (additional logs)
/root/.mina-network/mina-local-network-2-1-1/**/logs/*.log
```

Mount a volume to persist logs:

```shell
docker run ... --mount "type=bind,source=/tmp,dst=/root/logs" ...
```

## Mina Accounts Manager

The Mina Accounts Manager automates how users retrieve account information. Useful for parallel automated tests where each test needs isolated accounts.

### API Endpoints

| Method | Endpoint | Description |
|--------|----------|-------------|
| `GET` | `/acquire-account` | Get an unused account from the pool |
| `PUT` | `/release-account` | Return an account to the pool |
| `GET` | `/list-acquired-accounts` | List all currently acquired accounts |
| `PUT` | `/lock-account` | Lock an account on the daemon |
| `PUT` | `/unlock-account` | Unlock an account on the daemon |

### Acquire Account

```shell
curl http://127.0.0.1:8181/acquire-account
# Response: { "pk": "B62q...", "sk": "EKE..." }
```

Query parameters:
- `isRegularAccount=<boolean>` (default: `true`) - Set to `false` for zkApp accounts
- `unlockAccount=<boolean>` (default: `false`) - Unlock account on acquisition

### Release Account

```shell
curl -X PUT http://127.0.0.1:8181/release-account \
  -H 'Content-Type: application/json' \
  -d '{ "pk": "B62q...", "sk": "EKE..." }'
```

### List Acquired Accounts

```shell
curl http://127.0.0.1:8181/list-acquired-accounts
# Response: [ { "pk": "...", "sk": "..." }, ... ]
```

## GitHub Actions Integration

### Service Container Example

```yaml
jobs:
  my-job:
    services:
      mina-local-network:
        image: o1labs/mina-local-network:compatible-latest-lightnet
        env:
          NETWORK_TYPE: 'single-node'
          PROOF_LEVEL: 'none'
          LOG_LEVEL: 'Info'
        ports:
          - 3085:3085
          - 5432:5432
          - 8080:8080
          - 8181:8181
          - 8282:8282
        volumes:
          - /tmp:/root/logs
    steps:
      - name: Wait for Mina Network readiness
        uses: o1-labs/wait-for-mina-network-action@v1
        with:
          mina-graphql-port: 8080

      - name: Run tests
        run: npm test

      - name: Upload Mina logs
        uses: actions/upload-artifact@v3
        if: always()
        with:
          if-no-files-found: ignore
          name: mina-logs
          path: /tmp/*.log
          retention-days: 5
```

## Image Tags

Image tags follow this naming convention:

```
o1labs/mina-local-network:<branch>-latest-<profile>
```

Examples:
- `compatible-latest-lightnet` - Compatible branch with lightnet profile (no proofs, fast)
- `compatible-latest-devnet` - Compatible branch with devnet profile (full proofs)
- `develop-latest-lightnet` - Develop branch with lightnet profile

Where:
- **Branch prefix** (`compatible`, `develop`, `master`): Corresponds to the Mina GitHub repository branch
- **Profile suffix** (`lightnet`, `devnet`): The Dune profile used during the build
  - `lightnet`: Proof level set to `none`, faster for testing
  - `devnet`: Full proof generation

## Building Images

### Prerequisites

- Docker with buildx support

### Build All Images

```shell
./scripts/build-all.sh \
  --archs "amd64,arm64" \
  --mina-release nightly \
  --target-branches "compatible,develop" \
  --archive-api-version "0.0.8" \
  --accounts-manager-version "0.1.1" \
  --docker-hub-user "o1labs" \
  --docker-scripts-dir "./"
```

#### Build Script Options

| Option | Description |
|--------|-------------|
| `--archs` | Target architectures (comma-separated: `amd64`, `arm64`) |
| `--mina-release` | Release type: `nightly`, `alpha`, or `beta` |
| `--target-branches` | Mina branches to build (comma-separated) |
| `--archive-api-version` | Version of Archive-Node-API |
| `--accounts-manager-version` | Version of Mina Accounts Manager |
| `--docker-hub-user` | Docker Hub username |
| `--docker-scripts-dir` | Path to this repository |
| `--skip-push` | Build without pushing to Docker Hub |
| `--no-cache` | Disable Docker build cache |
| `--extra-docker-suffix` | Extra suffix for image tags |

### Build Single Image

```shell
./scripts/build-image.sh \
  --archs "amd64" \
  --mina-release nightly \
  --mina-branch compatible \
  --mina-profile devnet \
  --proof-level none \
  --archive-api-version "0.0.8" \
  --accounts-manager-version "0.1.1" \
  --docker-user "o1labs" \
  --tag "compatible-latest-lightnet" \
  --skip-push
```
