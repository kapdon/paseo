# Docker

This repo now ships a root multi-stage `Dockerfile` plus `docker-compose.yml` for the initial self-hosted stack:

- `paseo-server`
- `paseo-relay-self-hosted`
- `paseo-app`

## What is included

- **Server**: `@getpaseo/server`
- **Relay**: `@getpaseo/relay-self-hosted` — a thin self-hosted wrapper around the reusable `@getpaseo/relay` Cloudflare relay adapter, following the `xixu-me/paseo-relay` separation pattern
- **App**: `@getpaseo/app` web export only

## What is intentionally excluded

- `@getpaseo/desktop`
- `@getpaseo/website`
- `@getpaseo/cli`
- native mobile packaging
- coding-agent binaries inside the server image

## Build individual images

```bash
docker build --target server -t paseo-server .
docker build --target relay-self-hosted -t paseo-relay-self-hosted .
docker build --target app -t paseo-app .
```

Each target now has its own dependency/build stages so you can rebuild a single profile without invalidating unrelated service stages.

## Run the stack

```bash
# optional: customize published ports / public endpoints
cp .env.docker.example .env

docker compose up --build
```

Published host ports:

- app web UI: `http://localhost:8080`
- daemon/server: `http://localhost:6767`
- relay: `http://localhost:8787`

## Notes

- Ports bind to `127.0.0.1` by default for safer local-only access. If you want LAN/remote exposure, set `PASEO_BIND_HOST=0.0.0.0` intentionally and update the public endpoint / CORS / allowed-host settings in `.env`.
- The app image is reusable across environments: nginx writes `paseo-runtime-config.js` at container start from `PASEO_DAEMON_PUBLIC_ENDPOINT`, so changing the daemon endpoint no longer requires rebuilding the app image.
- The server talks to the relay internally at `relay:8080`, but advertises `PASEO_RELAY_PUBLIC_ENDPOINT` externally, defaulting to `localhost:8787` for local compose usage.
- Pairing links and browser access use `PASEO_APP_BASE_URL`, `PASEO_RELAY_PUBLIC_ENDPOINT`, `PASEO_CORS_ORIGINS`, and `PASEO_ALLOWED_HOSTS`; update them together when deploying beyond one machine.
- Docker builds are faster because dependency installation is isolated per service profile and uses cache-mounted package-manager downloads.
- Relay durable object state persists in the `relay-data` named volume.
- Server runtime state persists in the `server-data` named volume.
