#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-hostinger-devbox-ts}"
REMOTE_FRAGMENT="${REMOTE_FRAGMENT:-/tmp/wolfie-platform-lab-k8s-health.Caddyfile}"
REMOTE_CADDYFILE="${REMOTE_CADDYFILE:-/srv/agent-webhook-hub/Caddyfile}"
CADDY_CONTAINER="${CADDY_CONTAINER:-agent-webhook-hub-caddy-1}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8}"
HUB_DOMAIN="${HUB_DOMAIN:-hooks.wolfie.gg}"
MARKER="wolfie-platform-lab:k8s-health"

scp ops/caddy/k8s-health.Caddyfile "${REMOTE_HOST}:${REMOTE_FRAGMENT}"

ssh "${REMOTE_HOST}" "REMOTE_FRAGMENT='${REMOTE_FRAGMENT}' REMOTE_CADDYFILE='${REMOTE_CADDYFILE}' CADDY_CONTAINER='${CADDY_CONTAINER}' CADDY_IMAGE='${CADDY_IMAGE}' HUB_DOMAIN='${HUB_DOMAIN}' MARKER='${MARKER}' bash -s" <<'REMOTE'
set -euo pipefail
backup="${REMOTE_CADDYFILE}.bak.k8s-health.$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp)"

sudo cp "${REMOTE_CADDYFILE}" "${backup}"
sudo awk -v marker="${MARKER}" '
  $0 == "# BEGIN " marker { skipping=1; next }
  $0 == "# END " marker { skipping=0; next }
  $0 ~ /^# ---- K3s health API lab/ { next }
  $0 ~ /^k8s-health[.]wolfie[.]gg[[:space:]]*\{/ { legacy=1; depth=1; next }
  legacy {
    depth += gsub(/\{/, "{")
    depth -= gsub(/\}/, "}")
    if (depth <= 0) legacy=0
    next
  }
  !skipping { print }
' "${REMOTE_CADDYFILE}" > "${tmp}"
printf '\n' >> "${tmp}"
cat "${REMOTE_FRAGMENT}" >> "${tmp}"

sudo cp "${tmp}" "${REMOTE_CADDYFILE}.tmp.k8s-health"
docker run --rm --network agent-webhook-hub_web \
  -e HUB_DOMAIN="${HUB_DOMAIN}" \
  -v "${REMOTE_CADDYFILE}.tmp.k8s-health:/etc/caddy/Caddyfile:ro" \
  "${CADDY_IMAGE}" caddy validate --config /etc/caddy/Caddyfile

sudo sh -c "cat '${REMOTE_CADDYFILE}.tmp.k8s-health' > '${REMOTE_CADDYFILE}'"
if docker exec "${CADDY_CONTAINER}" grep -q "${MARKER}" /etc/caddy/Caddyfile; then
  docker exec "${CADDY_CONTAINER}" caddy reload --config /etc/caddy/Caddyfile
else
  docker restart "${CADDY_CONTAINER}" >/dev/null
fi
rm -f "${tmp}"
printf 'backup=%s\n' "${backup}"
REMOTE
