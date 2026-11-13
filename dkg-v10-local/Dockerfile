# Local OriginTrail DKG V10 node in mock-chain mode (no blockchain).
FROM node:22-bookworm

ARG DKG_VERSION=10.0.27
RUN npm install -g @origintrail-official/dkg@${DKG_VERSION} \
 && npm cache clean --force

# Node home: config.json, auth.token, keys and the oxigraph store. Mounted from the host.
ENV DKG_HOME=/data/dkg

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

EXPOSE 9200
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
