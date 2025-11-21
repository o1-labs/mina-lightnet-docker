FROM postgres:14-bookworm

ARG MINA_BRANCH=develop
ARG MINA_REPO=https://nightly.apt.packages.minaprotocol.com
ARG MINA_ACCOUNTS_MANAGER_VERSION=0.1.1
ARG ARCHIVE_NODE_API_VERSION=0.0.1
ARG MINA_PROFILE=devnet

RUN apt update && apt install -y --no-install-recommends python3 python3-pip jq wget curl psmisc libpq-dev libjemalloc-dev libffi-dev nginx netcat-traditional && apt clean && rm -rf /var/lib/apt/lists/*

ENV NODE_VERSION=20.11.1
ARG TARGETARCH

RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y nodejs=${NODE_VERSION}-1nodesource1 \
    && node --version \
    && npm --version

COPY ./configuration/mina-local-network/ /root/.mina-network/mina-local-network/
COPY ./configuration/nginx.conf /root/

COPY ./scripts/spinup-testnet.sh /root/
RUN chmod +x /root/spinup-testnet.sh

COPY ./scripts/wait-for-network.sh /root/
RUN chmod +x /root/wait-for-network.sh

# download mina-local-network.sh script
RUN mkdir -p /root/scripts/mina-local-network

RUN wget https://raw.githubusercontent.com/MinaProtocol/mina/compatible/scripts/mina-local-network/mina-local-network.sh -O /root/scripts/mina-local-network/mina-local-network.sh
RUN wget https://raw.githubusercontent.com/MinaProtocol/mina/compatible/scripts/mina-local-network/generate-mina-local-network-ledger.py -O /root/scripts/mina-local-network/generate-mina-local-network-ledger.py
RUN wget https://raw.githubusercontent.com/MinaProtocol/mina/compatible/scripts/mina-local-network/requirements.txt -O /root/scripts/mina-local-network/requirements.txt

RUN chmod +x /root/scripts/mina-local-network/mina-local-network.sh
RUN chmod +x /root/scripts/mina-local-network/generate-mina-local-network-ledger.py

RUN pip3 install --no-cache-dir --break-system-packages -r /root/scripts/mina-local-network/requirements.txt

# install mina
RUN wget -q ${MINA_REPO}/repo-signing-key.gpg -O /etc/apt/trusted.gpg.d/minaprotocol.gpg \
    && echo "deb ${MINA_REPO} bookworm ${MINA_BRANCH}" | tee /etc/apt/sources.list.d/mina.list \
    && apt update \
    && apt install -y --no-install-recommends mina-logproc mina-${MINA_PROFILE} mina-archive-devnet \
    && apt clean \
    && rm -rf /var/lib/apt/lists/*

# remove magic config files (it makes sense for artificial testnet only, like the one we are going to spin up)
# otherwise, if you try to run a node with such config, it will fail as devnet might contain some hardcoded data like fork config
# that will not be valid for other networks
RUN rm -f /var/lib/coda/config_*.json

# install Archive Node API
RUN printf '%s\n' \
  'registry=https://registry.npmjs.org/' \
  '@o1labs:registry=https://europe-southwest1-npm.pkg.dev/o1labs-192920/euro-npm/' \
  > /root/.npmrc \
 && npm install -g archive-node-graphql@${ARCHIVE_NODE_API_VERSION} \
 && rm /root/.npmrc

# install Mina Accounts Manager
RUN wget https://github.com/shimkiv/mina-accounts-manager/releases/download/v${MINA_ACCOUNTS_MANAGER_VERSION}/accounts-manager-${TARGETARCH} \
    && chmod +x accounts-manager-${TARGETARCH} \
    && mv accounts-manager-${TARGETARCH} /usr/local/bin/accounts-manager

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
ENV PROOF_LEVEL="full"
ENV LOG_LEVEL="Trace"
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres
ENV POSTGRES_DB=archive
ENV SLOT_TIME=20000

RUN mina --version

ENTRYPOINT [ "bash", "-c" ]
CMD [ "/root/spinup-testnet.sh" ]
