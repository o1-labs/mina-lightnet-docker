# Lightweight Mina Network Docker Images

Spin up a lightweight Mina network within the single container.

These Docker images provide a simple and efficient way to deploy and run lightweight Mina blockchain networks for testing purposes. It is an implementation of the [Dockerization of Mina local networks](https://github.com/o1-labs/rfcs/blob/main/0004-dockerised-local-network.md) RFC.

Each Docker image is packaged with the genesis ledger configuration with more than 1000 prefunded accounts. Each account has a balance of 1550 MINA.

## Related projects

- [Mina protocol](https://github.com/MinaProtocol/mina)
- [o1js](https://github.com/o1-labs/o1js)
- [zkapp-cli](https://github.com/o1-labs/zkapp-cli)
- [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API)
- [Wait for Mina network GitHub action](https://github.com/o1-labs/wait-for-mina-network-action)
- [Mina accounts manager](https://github.com/shimkiv/mina-accounts-manager)
- [Mina lightweight explorer](https://github.com/o1-labs/mina-lightweight-explorer)

## Related documentation

- [Testing zkApps with Lightnet](https://docs.minaprotocol.com/zkapps/testing-zkapps-lightnet)

## Specifications

- This Docker image exposes port `8080` that is served by the NGINX reverse proxy with proper cross-origin resource sharing (CORS) management and passes requests to an available Mina Daemon GraphQL endpoint.
- To ensure that the **o1js** zkApps applications work without additional environment configuration, you must use an endpoint like `http://localhost:8080/graphql` to communicate with the Mina GraphQL endpoint.

By default, containers run the [Mina Archive Node](https://docs.minaprotocol.com/node-operators/archive-node) along with the PostgreSQL RDBMS that stores the blockchain data.

- To prevent the Mina Archive Node and RDBMS from running in the container, set the `RUN_ARCHIVE_NODE` environment variable to `false`.

  ```shell
  docker run ... --env RUN_ARCHIVE_NODE="false" ...
  ```

Connection to the container's PostgreSQL can be used for other needs, including the [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API).

- The default PostgreSQL connection string is:

  ```shell
  postgresql://postgres:postgres@localhost:5432/archive
  ```

If no Mina Archive Node will run inside the container, then [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API) won't be available.

## Mina accounts manager

The Mina accounts manager helper tool, provided with the Docker images, automates how users retrieve account information.  
An example use case this application is parallel automated tests execution against the lightweight Mina network.

- Since executed in parallel, these tests should be isolated so they do not impact the work and environment of each other.
- This tool provides a way for humans and programs to get "unused" (not in use by anyone else) accounts at any particular point in time.

To keep the accounts pool available for other tasks, be sure to release used accounts after you've done with your work.

## Usage

### GitHub Actions CI/CD

Before the Mina network can be used in your job or jobs steps, it must reach the synchronized state after the corresponding [service container](https://docs.github.com/en/actions/using-containerized-services/about-service-containers) startup. You can use the [wait-for-mina-network](https://github.com/marketplace/actions/wait-for-mina-network) GitHub Action to automate this process.

### Single Node

```shell
docker run --rm --pull=always -it \
  --env NETWORK_TYPE="single-node" \
  --env PROOF_LEVEL="none" \
  --env LOG_LEVEL="Info" \
  -p 3085:3085 \
  -p 5432:5432 \
  -p 8080:8080 \
  -p 8181:8181 \
  -p 8282:8282 \
  o1labs/mina-local-network:berkeley-latest-lightnet
```

#### Single Node network properties

- Transaction finality (k) in 30 blocks
- 720 slots per epoch
- New blocks are produced every ~20-40 seconds
- 5-8 transactions per block
- ~850-970 MB of RAM consumption after initial spike and if stays alive during less than 2 hours ~= 1/2 epoch
- The startup and sync time is ~1-2 minutes

#### Single Node logs

By default, logs produced by different processes will be redirected into the files located by the following path pattern inside the container:

```shell
/root/logs/*.log
```

You can always use Docker Volumes to map the corresponding logs storage path inside the container to the host machine.

```shell
docker run ... --mount "type=bind,source=/tmp,dst=/root/logs" ...
```

It is especially useful if you want to keep the logs after the container is stopped and deleted. For example when used in CI/CD pipelines.

#### [GitHub Actions](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions#jobsjob_idservices) example

```yaml
...
jobs:
  my-job:
    ...
    services:
      mina-local-network:
        image: o1labs/mina-local-network:berkeley-latest-lightnet
        env:
          NETWORK_TYPE: 'single-node'
          PROOF_LEVEL: 'none'
          LOG_LEVEL: 'Info'
        ports:
          - 3085:3085
          - 5432:5432
          - 8080:8080
          - 8181:8181
        volumes:
          - /tmp:/root/logs
      ...
    steps:
      - name: Wait for Mina Network readiness
        uses: o1-labs/wait-for-mina-network-action@v1
        with:
          mina-graphql-port: 8080
      ...
      - name: Upload Mina logs
        uses: actions/upload-artifact@v3
        with:
          if-no-files-found: ignore
          name: mina-logs
          path: /tmp/*.log
          retention-days: 5
```

#### Single Node services topology

```shell
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

**Where**:

- The Mina multi-purpose Daemon is the core of Mina blockchain network. This single Mina Daemon process acts as the block producer, snark worker and as the seed node at the same time.
- The NGINX reverse proxy is used to provide the Mina GraphQL endpoint with proper CORS management.
- The PostgreSQL is **optional** RDBMS process that is used to store the blockchain data for Mina Archive process.
- The [Mina Accounts Manager](https://github.com/shimkiv/mina-accounts-manager) is a helper tool that automates how users retrieve account information.
- The [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API) is **optional** helper tool that provides a REST API to the PostgreSQL RDBMS.
- Mina Archive Node **optional** Mina Archive process that Mina Daemon talks to in order to preserve blockchain data.

#### Single Node exposed ports reference

- **3085**: Mina Daemon GraphQL endpoint
- **5432**: PostgreSQL RDBMS
- **8080**: NGINX reverse proxy against Mina Daemon GraphQL endpoint
- **8181**: Mina Accounts Manager
- **8282**: Archive-Node-API

### Multi-Node

```shell
docker run --rm --pull=always -it \
 --env NETWORK_TYPE="multi-node" \
 --env PROOF_LEVEL="none" \
 --env LOG_LEVEL="Info" \
 -p 4001:4001 \
 -p 4006:4006 \
 -p 5001:5001 \
 -p 5432:5432 \
 -p 6001:6001 \
 -p 8080:8080 \
 -p 8181:8181 \
 -p 8282:8282 \
 o1labs/mina-local-network:berkeley-latest-lightnet
```

#### Multi-Node network properties

- Transaction finality (k) in 30 blocks
- 720 slots per epoch
- New blocks are produced every ~20-40 seconds
- 5-8 transactions per block
- ~5.5-6+ GB of RAM consumption
- The startup and sync time is ~4-6 minutes

#### Multi-Node logs

By default, logs produced by different processes will be redirected into the files located by the following path patterns inside the container:

```shell
/root/logs/*.log
/root/.mina-network/mina-local-network-2-1-1/**/logs/*.log
```

#### Multi-Node services topology

```shell
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

**Where**:

- The Mina nodes are the core of Mina blockchain network. Independent processes that represent seed nodes, block producers, snark coordinators, snark workers and non block-producing nodes.
- The NGINX reverse proxy is used to provide the Mina GraphQL endpoint with proper CORS management.
- The PostgreSQL is **optional** RDBMS process that is used to store the blockchain data for Mina Archive process.
- The [Mina Accounts Manager](https://github.com/shimkiv/mina-accounts-manager) is a helper tool that automates how users retrieve account information.
- The [Archive-Node-API](https://github.com/o1-labs/Archive-Node-API) is **optional** helper tool that provides a REST API to the PostgreSQL RDBMS.
- Mina Archive Node **optional** Mina Archive process that Mina Daemons talk to in order to preserve blockchain data.

#### Multi-Node exposed ports reference

- **4001**: Whale #1 Mina Daemon GraphQL endpoint
- **4006**: Whale #2 Mina Daemon GraphQL endpoint
- **5001**: Fish #1 Mina Daemon GraphQL endpoint
- **5432**: PostgreSQL RDBMS
- **6001**: Non block-producing node #1 Mina Daemon GraphQL endpoint
- **8080**: NGINX reverse proxy against Whale #2 Mina Daemon GraphQL endpoint
- **8181**: Mina Accounts Manager
- **8282**: Archive-Node-API

## Image tags anatomy

Several image tags are available for download like:

- `berkeley-latest-lightnet`

where:

- The `berkeley` prefix corresponds to the Mina GitHub repository branch
- The `lightnet` suffix corresponds to the Dune profile that was used during the application build procedure for current image tag

## Mina accounts manager API

The Mina accounts manager that runs inside the container provides the following API:

```shell
-----------------------------
.:: Mina Accounts-Manager ::.
-----------------------------

Application initialized and is running at: http://localhost:8181
Available endpoints:

   HTTP GET:
   http://localhost:8181/acquire-account
   Supported Query params:
                           isRegularAccount=<boolean>, default: true
                           Useful if you need to get non-zkApp account.

                           unlockAccount=<boolean>, default: false
                           Useful if you need to get unlocked account.
   Returns JSON account key-pair:
   { pk:"", sk:"" }

   HTTP PUT:
   http://localhost:8181/release-account
   Accepts JSON account key-pair as request payload:
   { pk:"", sk:"" }
   Returns JSON status message

   HTTP GET:
   http://localhost:8181/list-acquired-accounts
   Returns JSON list of acquired accounts key-pairs:
   [ { pk:"", sk:"" }, ... ]

   HTTP PUT:
   http://localhost:8383/lock-account
   Accepts JSON account key-pair as request payload:
   { pk:"", sk:"" }
   Returns JSON status message

   HTTP PUT:
   http://localhost:8181/unlock-account
   Accepts JSON account key-pair as request payload:
   { pk:"", sk:"" }
   Returns JSON status message

Operating with:
   Mina Genesis ledger:   /root/.mina-network/mina-local-network-2-1-1/daemon.json
   Mina GraphQL endpoint: http://localhost:8080/graphql
```
