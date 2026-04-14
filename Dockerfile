# syntax=docker/dockerfile:1.7-labs

FROM node:22-bookworm-slim AS base

WORKDIR /workspace

FROM base AS app-deps

COPY package.json package-lock.json ./
COPY scripts/postinstall-patches.mjs scripts/postinstall-patches.mjs
COPY patches ./patches
COPY docker/rewrite-workspaces.mjs docker/rewrite-workspaces.mjs
COPY packages/app/package.json packages/app/package.json
COPY packages/expo-two-way-audio/package.json packages/expo-two-way-audio/package.json
COPY packages/highlight/package.json packages/highlight/package.json
COPY packages/relay/package.json packages/relay/package.json
COPY packages/server/package.json packages/server/package.json

RUN node docker/rewrite-workspaces.mjs \
    packages/expo-two-way-audio \
    packages/highlight \
    packages/relay \
    packages/server \
    packages/app

RUN --mount=type=cache,target=/root/.npm \
    npm ci --include-workspace-root --workspaces

FROM app-deps AS app-builder

COPY app.json tsconfig.base.json ./
COPY docker/patch-app-runtime-config.mjs docker/patch-app-runtime-config.mjs
COPY packages/app ./packages/app
COPY packages/expo-two-way-audio ./packages/expo-two-way-audio
COPY packages/highlight ./packages/highlight
COPY packages/relay ./packages/relay
COPY packages/server ./packages/server

RUN npm run build:web --workspace=@getpaseo/app
RUN node docker/patch-app-runtime-config.mjs packages/app/dist

FROM base AS server-deps

COPY package.json package-lock.json ./
COPY scripts/postinstall-patches.mjs scripts/postinstall-patches.mjs
COPY patches ./patches
COPY docker/rewrite-workspaces.mjs docker/rewrite-workspaces.mjs
COPY packages/highlight/package.json packages/highlight/package.json
COPY packages/relay/package.json packages/relay/package.json
COPY packages/server/package.json packages/server/package.json

RUN node docker/rewrite-workspaces.mjs \
    packages/highlight \
    packages/relay \
    packages/server

RUN --mount=type=cache,target=/root/.npm \
    npm ci --include-workspace-root --workspaces

FROM server-deps AS server-builder

COPY packages/highlight ./packages/highlight
COPY packages/relay ./packages/relay
COPY packages/server ./packages/server

RUN npm run build --workspace=@getpaseo/highlight \
 && npm run build --workspace=@getpaseo/relay \
 && npm run build --workspace=@getpaseo/server

FROM base AS relay-deps

COPY package.json package-lock.json tsconfig.base.json ./
COPY scripts/postinstall-patches.mjs scripts/postinstall-patches.mjs
COPY patches ./patches
COPY docker/rewrite-workspaces.mjs docker/rewrite-workspaces.mjs
COPY packages/relay/package.json packages/relay/package.json
COPY packages/relay-self-hosted/package.json packages/relay-self-hosted/package.json
COPY packages/relay-self-hosted/tsconfig.json packages/relay-self-hosted/tsconfig.json
COPY packages/relay-self-hosted/wrangler.jsonc packages/relay-self-hosted/wrangler.jsonc
COPY packages/relay-self-hosted/config.capnp packages/relay-self-hosted/config.capnp

RUN node docker/rewrite-workspaces.mjs \
    packages/relay \
    packages/relay-self-hosted

RUN --mount=type=cache,target=/root/.npm \
    npm ci --include-workspace-root --workspaces

FROM relay-deps AS relay-self-hosted-builder

COPY packages/relay ./packages/relay
COPY packages/relay-self-hosted ./packages/relay-self-hosted

RUN npm run build --workspace=@getpaseo/relay-self-hosted

FROM node:22-bookworm-slim AS server

WORKDIR /app

ENV NODE_ENV=production \
    PASEO_HOME=/var/lib/paseo \
    PASEO_LISTEN=0.0.0.0:6767

COPY --from=server-deps /workspace/node_modules ./node_modules
COPY --from=server-builder /workspace/packages/highlight ./packages/highlight
COPY --from=server-builder /workspace/packages/relay ./packages/relay
COPY --from=server-builder /workspace/packages/server ./packages/server

RUN mkdir -p public /var/lib/paseo

EXPOSE 6767
VOLUME ["/var/lib/paseo"]

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:6767/api/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "packages/server/dist/server/server/index.js"]

FROM node:22-bookworm-slim AS relay-self-hosted

ARG TARGETARCH

RUN apt-get update \
 && apt-get install -y --no-install-recommends ca-certificates \
 && rm -rf /var/lib/apt/lists/* \
 && case "${TARGETARCH}" in \
      amd64) WORKERD_PKG="@cloudflare/workerd-linux-64" ;; \
      arm64) WORKERD_PKG="@cloudflare/workerd-linux-arm64" ;; \
      *) echo "Unsupported TARGETARCH: ${TARGETARCH}" && exit 1 ;; \
    esac \
 && npm install -g "${WORKERD_PKG}" \
 && ln -s "/usr/local/lib/node_modules/${WORKERD_PKG}/bin/workerd" /usr/local/bin/workerd

WORKDIR /worker

COPY --from=relay-self-hosted-builder /workspace/packages/relay-self-hosted/dist-oci ./dist-oci
COPY --from=relay-self-hosted-builder /workspace/packages/relay-self-hosted/config.capnp ./config.capnp

RUN mkdir -p /var/lib/paseo-relay/do \
 && chown -R node:node /worker /var/lib/paseo-relay

EXPOSE 8080
VOLUME ["/var/lib/paseo-relay/do"]
USER node

HEALTHCHECK --interval=15s --timeout=5s --start-period=20s --retries=5 \
  CMD node -e "fetch('http://127.0.0.1:8080/health').then((r)=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["workerd", "serve", "config.capnp", "--directory-path", "relay-storage=/var/lib/paseo-relay/do"]

FROM nginx:1.27-alpine AS app

ENV PASEO_DAEMON_PUBLIC_ENDPOINT=localhost:6767

COPY docker/nginx-app.conf /etc/nginx/conf.d/default.conf
COPY docker/40-write-runtime-config.sh /docker-entrypoint.d/40-write-runtime-config.sh
RUN chmod +x /docker-entrypoint.d/40-write-runtime-config.sh
COPY --from=app-builder /workspace/packages/app/dist /usr/share/nginx/html

EXPOSE 80

HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=5 \
  CMD wget -qO- http://127.0.0.1/ >/dev/null || exit 1
