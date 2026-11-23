FROM postgres:14-bookworm

ARG MINA_BRANCH=develop
ARG MINA_REPO=https://nightly.apt.packages.minaprotocol.com
ARG MINA_ACCOUNTS_MANAGER_VERSION=0.1.2
ARG ARCHIVE_NODE_API_VERSION=2.0.0
ARG MINA_PROFILE=devnet
# Extra profile like lightnet. Selects a variant deb (mina-<profile>-generic-<extra>).
# Only the nightly repo publishes such variant debs.
ARG MINA_EXTRA_PROFILE
# Exact deb version to install (e.g. 4.0.2-84b8d96). Empty = newest in the component.
ARG MINA_DEB_VERSION
# Profile the daemon selects at runtime (dev, devnet, lightnet, mainnet).
# Since Mina 4.0.2 the daemon ships as one network-free binary (mina-generic) and
# reads its profile from /etc/coda/build_config/PROFILE (or MINA_PROFILE env).
# Empty = keep the profile shipped by the installed deb.
ARG MINA_RUNTIME_PROFILE
ARG PROOF_LEVEL=full
ARG EXPLORER_VERSION=v0.2.2
# minimina runs the network (https://github.com/o1-labs/minimina)
ARG MINIMINA_VERSION=0.3.1

ARG TARGETARCH

# Build MINA debian package name (use -generic configless variant).
# When MINA_EXTRA_PROFILE is set (e.g. "lightnet"), append it as a package-name
# suffix so the corresponding variant deb is installed (mina-devnet-generic-lightnet).
ENV MINA_DEB_NAME="mina-${MINA_PROFILE}-generic${MINA_EXTRA_PROFILE:+-${MINA_EXTRA_PROFILE}}"
# Optional "=<version>" pin appended to every mina deb below.
ENV MINA_DEB_PIN="${MINA_DEB_VERSION:+=${MINA_DEB_VERSION}}"

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

# install Node.js 22.x LTS (don't pin exact version — nodesource rotates them).
# @o1-labs/mina-archive-node-graphql >= 2.0.0 requires Node >= 22.12.
# AllowWeakRepositories lets nodesource's setup script's internal `apt-get update`
# tolerate transient "weak security information" errors on Debian's bookworm-updates
# InRelease — without it the setup aborts and apt silently falls back to Debian's
# nodejs (which omits npm), breaking the next step.
RUN echo 'Acquire::AllowWeakRepositories "true";' > /etc/apt/apt.conf.d/99-allow-weak-repos \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && node --version \
    && npm --version \
    && rm /etc/apt/apt.conf.d/99-allow-weak-repos

# The prefunded accounts of the genesis ledger: those of daemon.json with a
# private key, and their key files, which the accounts manager imports into
# the daemon for unlockAccount=true. The other 7 accounts of daemon.json were
# the keys of mina-local-network.sh's nodes and held most of the stake; with
# them, the network's block producers would win fewer slots.
COPY ./configuration/key-pairs/ /root/lightnet/key-pairs/
COPY ./configuration/mina-local-network/daemon.json /root/lightnet/daemon.json
RUN chmod 0700 /root/lightnet/key-pairs \
    && chmod 0600 /root/lightnet/key-pairs/* \
    && jq '{ledger: {accounts: [.ledger.accounts[] | select(.sk)]}}' /root/lightnet/daemon.json \
        > /root/lightnet/accounts.json
COPY ./configuration/nginx.conf /root/

COPY ./scripts/spinup-testnet.sh ./scripts/lightnet-spec.sh /root/
RUN chmod +x /root/spinup-testnet.sh /root/lightnet-spec.sh

COPY ./scripts/wait-for-network.sh /root/
RUN chmod +x /root/wait-for-network.sh

# install mina
RUN curl -fsSL ${MINA_REPO}/repo-signing-key.gpg -o /etc/apt/trusted.gpg.d/minaprotocol.gpg \
    && echo "deb ${MINA_REPO} bookworm ${MINA_BRANCH}" | tee /etc/apt/sources.list.d/mina.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        mina-logproc${MINA_DEB_PIN} ${MINA_DEB_NAME}${MINA_DEB_PIN} mina-archive-${MINA_PROFILE}${MINA_DEB_PIN} \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/*

# install minimina from mina's stable repository, signed with the same key
RUN echo "deb https://stable.apt.packages.minaprotocol.com bookworm stable" \
        > /etc/apt/sources.list.d/minimina.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends minimina=${MINIMINA_VERSION}-1 \
    && apt-get clean \
    && rm -rf /var/lib/apt/lists/* \
    && minimina --version

# Select the runtime profile (see MINA_RUNTIME_PROFILE above).
RUN if [ -n "${MINA_RUNTIME_PROFILE}" ]; then \
      mkdir -p /etc/coda/build_config \
      && printf '%s' "${MINA_RUNTIME_PROFILE}" > /etc/coda/build_config/PROFILE; \
    fi

# remove magic config files (it makes sense for artificial testnet only, like the one we are going to spin up)
# otherwise, if you try to run a node with such config, it will fail as devnet might contain some hardcoded data like fork config
# that will not be valid for other networks
RUN rm -f /var/lib/coda/config_*.json

# install Mina Archive Node GraphQL API from npm registry.
# Use the scoped @o1-labs publish — the unscoped `mina-archive-node-graphql`
# is stale (last 0.0.9, Dec 2025). 2.0.0 is the first scoped release that shares
# its major with the archive SDKs (schemaVersion "2.0"). See issue #30.
RUN npm install -g @o1-labs/mina-archive-node-graphql@${ARCHIVE_NODE_API_VERSION}

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

# static landing page (/) and docs page (/docs) served by NGINX on port 8080
COPY ./configuration/landing/ /usr/share/nginx/landing/
COPY ./configuration/docs/ /usr/share/nginx/docs/

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
