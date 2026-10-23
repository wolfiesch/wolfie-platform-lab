#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-hostinger-devbox-ts}"
REMOTE_FRAGMENT_DIR="${REMOTE_FRAGMENT_DIR:-/tmp/wolfie-platform-lab-caddy}"
REMOTE_CADDYFILE="${REMOTE_CADDYFILE:-/srv/agent-webhook-hub/Caddyfile}"
CADDY_CONTAINER="${CADDY_CONTAINER:-agent-webhook-hub-caddy-1}"
CADDY_IMAGE="${CADDY_IMAGE:-caddy:2.8}"
HUB_DOMAIN="${HUB_DOMAIN:-hooks.wolfie.gg}"
MARKER_PREFIX="wolfie-platform-lab:"

rsync -az --delete ops/caddy/ "${REMOTE_HOST}:${REMOTE_FRAGMENT_DIR}/"

ssh "${REMOTE_HOST}" "REMOTE_FRAGMENT_DIR='${REMOTE_FRAGMENT_DIR}' REMOTE_CADDYFILE='${REMOTE_CADDYFILE}' CADDY_CONTAINER='${CADDY_CONTAINER}' CADDY_IMAGE='${CADDY_IMAGE}' HUB_DOMAIN='${HUB_DOMAIN}' MARKER_PREFIX='${MARKER_PREFIX}' bash -s" <<'REMOTE'
set -euo pipefail
backup="${REMOTE_CADDYFILE}.bak.managed-routes.$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$(mktemp)"

sudo cp "${REMOTE_CADDYFILE}" "${backup}"
# omp.wolfie.gg belongs to omp-episodic-memory (deploy/ompdocs.caddy, the
# `# BEGIN ompdocs` block); this rewrite must leave it alone.
sudo awk -v marker_prefix="${MARKER_PREFIX}" '
  index($0, "# BEGIN " marker_prefix) == 1 { managed=1; next }
  index($0, "# END " marker_prefix) == 1 { managed=0; next }
  $0 ~ /^# ---- K3s health API lab/ { next }
  $0 ~ /^# ---- Freakoff / { next }
  $0 ~ /^(k8s-health|freakoff)[.]wolfie[.]gg[[:space:]]*\{/ { legacy=1; depth=1; next }
  legacy {
    depth += gsub(/\{/, "{")
    depth -= gsub(/\}/, "}")
    if (depth <= 0) legacy=0
    next
  }
  !managed { print }
' "${REMOTE_CADDYFILE}" > "${tmp}"

for fragment in "${REMOTE_FRAGMENT_DIR}"/*.Caddyfile; do
  printf '\n' >> "${tmp}"
  cat "${fragment}" >> "${tmp}"
done

# Dropping the retired wolfie-platform-lab:omp block is only safe once the
# ompdocs block serves omp.wolfie.gg; otherwise the host would lose its site.
if [ "$(grep -c -x -F '# BEGIN ompdocs' "${tmp}" || true)" != 1 ] ||
  [ "$(grep -c -x -F '# END ompdocs' "${tmp}" || true)" != 1 ] ||
  ! awk '
    $0 == "# BEGIN ompdocs" { inside=1; next }
    $0 == "# END ompdocs" { inside=0; next }
    inside && /^omp[.]wolfie[.]gg[[:space:]]*\{[[:space:]]*$/ { hosts++ }
    END { exit !(hosts == 1 && !inside) }
  ' "${tmp}"; then
  rm -f "${tmp}"
  printf 'refusing: %s must hold exactly one ompdocs block containing omp.wolfie.gg; run the omp-episodic-memory edge cutover first (backup=%s)\n' "${REMOTE_CADDYFILE}" "${backup}" >&2
  exit 1
fi

sudo cp "${tmp}" "${REMOTE_CADDYFILE}.tmp.managed-routes"
docker run --rm --network agent-webhook-hub_web \
  -e HUB_DOMAIN="${HUB_DOMAIN}" \
  -v "${REMOTE_CADDYFILE}.tmp.managed-routes:/etc/caddy/Caddyfile:ro" \
  "${CADDY_IMAGE}" caddy validate --config /etc/caddy/Caddyfile

sudo sh -c "cat '${REMOTE_CADDYFILE}.tmp.managed-routes' > '${REMOTE_CADDYFILE}'"
if docker exec "${CADDY_CONTAINER}" grep -q "${MARKER_PREFIX}" /etc/caddy/Caddyfile; then
  docker exec "${CADDY_CONTAINER}" caddy reload --config /etc/caddy/Caddyfile
else
  docker restart "${CADDY_CONTAINER}" >/dev/null
fi
rm -f "${tmp}"
printf 'backup=%s\n' "${backup}"
REMOTE
