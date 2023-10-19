FROM postgres:14-bookworm

RUN apt update && apt install -y --no-install-recommends python3 python3-pip jq wget curl psmisc libpq-dev libjemalloc-dev libffi-dev nginx netcat-traditional && apt clean && rm -rf /var/lib/apt/lists/*

ENV NODE_VERSION=20.8.1
RUN curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.39.0/install.sh | bash
ENV NVM_DIR=/root/.nvm
RUN . "$NVM_DIR/nvm.sh" && nvm install ${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm use v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && nvm alias default v${NODE_VERSION}
RUN . "$NVM_DIR/nvm.sh" && npm install -g npm
ENV PATH="/root/.nvm/versions/node/v${NODE_VERSION}/bin/:${PATH}"
RUN node --version
RUN npm --version

COPY mina-local-network-2-1-1/ /root/.mina-network/mina-local-network-2-1-1/
COPY nginx.conf /root/
COPY spinup-testnet.sh /root/
COPY mina-local-network.sh /root/
COPY drop_tables.sql /root/
COPY create_schema.sql /root/
COPY zkapp_tables.sql /root/
COPY mina.exe /root/
COPY archive.exe /root/
COPY libp2p_helper /root/
COPY Archive-Node-API/ /root/Archive-Node-API/
# COPY accounts-manager /root/

WORKDIR /root

RUN chmod +x mina.exe
RUN chmod +x archive.exe
RUN chmod +x libp2p_helper
RUN chmod +x spinup-testnet.sh
RUN chmod +x mina-local-network.sh
# RUN chmod +x accounts-manager

EXPOSE 3085
EXPOSE 4001
EXPOSE 4006
EXPOSE 5001
EXPOSE 5432
EXPOSE 6001
EXPOSE 8080
# EXPOSE 8181
EXPOSE 8282

ENV RUN_ARCHIVE_NODE="true"
ENV NETWORK_TYPE="single-node"
ENV PROOF_LEVEL=full
ENV MINA_LIBP2P_HELPER_PATH=/root/libp2p_helper
ENV POSTGRES_USER=postgres
ENV POSTGRES_PASSWORD=postgres
ENV POSTGRES_DB=archive

RUN ./mina.exe advanced compile-time-constants

ENTRYPOINT [ "bash", "-c" ]
CMD [ "/root/spinup-testnet.sh" ]
