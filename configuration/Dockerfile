FROM ubuntu:22.04

RUN apt update && apt install -y --no-install-recommends python3 python3-pip jq wget curl psmisc libpq-dev libjemalloc-dev libffi7 nginx && apt clean && rm -rf /var/lib/apt/lists/*
COPY libssl1.1_1.1.1f-1ubuntu2.19_amd64.deb /root/
RUN dpkg -i /root/libssl1.1_1.1.1f-1ubuntu2.19_amd64.deb && rm /root/libssl1.1_1.1.1f-1ubuntu2.19_amd64.deb

COPY mina-local-network-2-1-1/ /root/.mina-network/mina-local-network-2-1-1/
COPY nginx.conf /root/
COPY spinup-testnet.sh /root/
COPY mina-local-network.sh /root/
COPY mina.exe /root/
COPY libp2p_helper /root/
# COPY accounts-manager /root/

WORKDIR /root

RUN chmod +x mina.exe
RUN chmod +x libp2p_helper
RUN chmod +x spinup-testnet.sh
RUN chmod +x mina-local-network.sh
# RUN chmod +x accounts-manager

EXPOSE 3085
EXPOSE 4001
EXPOSE 4006
EXPOSE 5001
EXPOSE 6001
EXPOSE 8080
# EXPOSE 8181

ENV NETWORK_TYPE="single-node"
ENV PROOF_LEVEL=full
ENV MINA_LIBP2P_HELPER_PATH=/root/libp2p_helper

RUN ./mina.exe advanced compile-time-constants

ENTRYPOINT [ "bash", "-c" ]
CMD [ "/root/spinup-testnet.sh" ]
