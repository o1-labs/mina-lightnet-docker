FROM postgres:14-bookworm

ARG MINA_BRANCH=develop
ARG MINA_REPO=https://nightly.apt.packages.minaprotocol.com
ARG MINA_ACCOUNTS_MANAGER_VERSION=0.1.2
ARG ARCHIVE_NODE_API_VERSION=0.0.8
ARG MINA_PROFILE=devnet
# Extra profile like lightnet
ARG MINA_EXTRA_PROFILE
ARG PROOF_LEVEL=full
ARG EXPLORER_VERSION=v0.2.2

ENV NODE_VERSION=20.11.1
ARG TARGETARCH

# Build MINA debian package name (use -generic configless variant)
ENV MINA_DEB_NAME="mina-${MINA_PROFILE}-generic"

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
RUN apt-get update && apt-get install -y --no-install-recommends \
    python3 \
    python3-pip \
    jq \
    curl \
    psmisc \
    libpq-dev \
    libjemalloc-dev \
    libffi-dev \
    nginx \
    netcat-traditional \
    && apt-get clean && rm -rf /var/lib/apt/lists/*

# install Node.js
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs=${NODE_VERSION}-1nodesource1 \
    && node --version \
    && npm --version

COPY ./configuration/mina-local-network/ /root/.mina-network/
COPY ./configuration/nginx.conf /root/

COPY ./scripts/spinup-testnet.sh /root/
RUN chmod +x /root/spinup-testnet.sh

COPY ./scripts/wait-for-network.sh /root/
RUN chmod +x /root/wait-for-network.sh

ENV MINA_COMMIT=aa93c44428e7c73cd7b77900634522108b746d18

# download mina-local-network.sh script
RUN mkdir -p /root/scripts/mina-local-network

RUN curl -fsSL https://raw.githubusercontent.com/MinaProtocol/mina/${MINA_COMMIT}/scripts/mina-local-network/mina-local-network.sh -o /root/scripts/mina-local-network/mina-local-network.sh \
    && curl -fsSL https://raw.githubusercontent.com/MinaProtocol/mina/${MINA_COMMIT}/scripts/mina-local-network/generate-mina-local-network-ledger.py -o /root/scripts/mina-local-network/generate-mina-local-network-ledger.py \
    && curl -fsSL https://raw.githubusercontent.com/MinaProtocol/mina/${MINA_COMMIT}/scripts/mina-local-network/requirements.txt -o /root/scripts/mina-local-network/requirements.txt \
    && chmod +x /root/scripts/mina-local-network/mina-local-network.sh \
    && chmod +x /root/scripts/mina-local-network/generate-mina-local-network-ledger.py \
    && pip3 install --no-cache-dir --break-system-packages -r /root/scripts/mina-local-network/requirements.txt

# install mina
RUN curl -fsSL ${MINA_REPO}/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/minaprotocol.gpg \
    && echo "deb ${MINA_REPO} bookworm ${MINA_BRANCH}" | tee /etc/apt/sources.list.d/mina.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends mina-logproc ${MINA_DEB_NAME} mina-archive-${MINA_PROFILE} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# remove magic config files (it makes sense for artificial testnet only, like the one we are going to spin up)
# otherwise, if you try to run a node with such config, it will fail as devnet might contain some hardcoded data like fork config
# that will not be valid for other networks
RUN rm -f /var/lib/coda/config_*.json

# install Mina Archive Node GraphQL API from npm registry
RUN npm install -g mina-archive-node-graphql@${ARCHIVE_NODE_API_VERSION}

# install Mina Accounts Manager
RUN curl -fsSL https://github.com/o1-labs/mina-accounts-manager/releases/download/v${MINA_ACCOUNTS_MANAGER_VERSION}/accounts-manager-${TARGETARCH} -o accounts-manager-${TARGETARCH} \
    && chmod +x accounts-manager-${TARGETARCH} \
    && mv accounts-manager-${TARGETARCH} /usr/local/bin/accounts-manager

# install Mina Lightweight Explorer (static files only, no build step)
RUN mkdir -p /usr/share/nginx/explorer \
    && curl -fsSL "https://github.com/o1-labs/mina-lightweight-explorer/archive/refs/tags/${EXPLORER_VERSION}.tar.gz" \
    | tar -xz --strip-components=1 -C /usr/share/nginx/explorer \
    && rm -f /usr/share/nginx/explorer/LICENSE /usr/share/nginx/explorer/README.md \
             /usr/share/nginx/explorer/screenshot-dark.png /usr/share/nginx/explorer/server.js

WORKDIR /root

EXPOSE 3085
EXPOSE 4001
EXPOSE 4006
EXPOSE 5001
EXPOSE 5432
EXPOSE 6001
EXPOSE 8080
EXPOSE 8282

ENV RUN_ARCHIVE_NODE="true"
ENV NETWORK_TYPE="single-node"
ENV PROOF_LEVEL="${PROOF_LEVEL}"
# Record the compile-time proof level so the entrypoint can validate runtime overrides
ENV COMPILED_PROOF_LEVEL="${PROOF_LEVEL}"
ENV LOG_LEVEL="Trace"
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres
ENV POSTGRES_DB=archive
ENV SLOT_TIME=20000

RUN mina --version

ENTRYPOINT [ "bash", "-c" ]
CMD [ "/root/spinup-testnet.sh" ]
