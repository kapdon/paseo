#!/bin/sh
set -eu

endpoint="${PASEO_DAEMON_PUBLIC_ENDPOINT:-localhost:6767}"
escaped_endpoint="$(printf '%s' "$endpoint" | sed 's/\\/\\\\/g; s/"/\\"/g')"

printf 'window.__PASEO_RUNTIME_CONFIG__ = { daemonEndpoint: "%s" };\n' "$escaped_endpoint" \
  > /usr/share/nginx/html/paseo-runtime-config.js
