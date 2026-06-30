# Freak Off migration rollback snapshot

Captured before any Kubernetes manifests or production edge cutover for Freak Off.

## Current edge route

```caddyfile
# ---- Freakoff (Next.js archive-upload app) added 2026-06-24 ----
freakoff.wolfie.gg {
	encode zstd gzip
	reverse_proxy freakoff-nextjs:3000
}
```

## Current containers

| Container | Image tag | Image ID | Command | User | Networks | Mounts |
|---|---|---|---|---|---|---|
| `freakoff-nextjs` | `freakoff-web` | `sha256:22e2c6a6893adb9b71a48e75446cb1ce59b92fc2daa96023c30cec89eb6b0b1e` | `npm run start` | `nextjs` | `agent-webhook-hub_web`, `insforge_insforge-network` | `freakoff_upload_tmp:/app/uploads` |
| `freakoff-worker` | `freakoff-worker` | `sha256:43c78d12a3a97e38f8d9ac62a2833a50194af8f32758f4d58a125cf80cc43cdb` | `npm run worker` | `nextjs` | `insforge_insforge-network` | `freakoff_upload_tmp:/app/uploads` |

Authoritative compose file on VPS:

```text
/home/wolfie/stacks/freakoff/docker-compose.yml
```

Compose shape:

```text
web: Dockerfile, container freakoff-nextjs, env_file .env, upload_tmp:/app/uploads, networks insforge_insforge-network + agent-webhook-hub_web
worker: Dockerfile, container freakoff-worker, command npm run worker, env_file .env, upload_tmp:/app/uploads, network insforge_insforge-network
```

## Environment variable names only

No values captured here.

### `freakoff-nextjs`

```text
SPOTIFY_CLIENT_ID
WORKER_POLL_INTERVAL_MS
INSFORGE_API_KEY
UPLOAD_DIR
SPOTIFY_CLIENT_SECRET
APP_URL
NODE_ENV
MAX_UPLOAD_SIZE_MB
INSFORGE_ARCHIVE_BUCKET
DATABASE_URL
INSFORGE_API_URL
PORT
HOSTNAME
```

### `freakoff-worker`

```text
INSFORGE_API_KEY
SPOTIFY_CLIENT_SECRET
INSFORGE_API_URL
NODE_ENV
INSFORGE_ARCHIVE_BUCKET
APP_URL
UPLOAD_DIR
SPOTIFY_CLIENT_ID
DATABASE_URL
MAX_UPLOAD_SIZE_MB
WORKER_POLL_INTERVAL_MS
PORT
HOSTNAME
```

## Current public behavior

```text
https://freakoff.wolfie.gg/        -> HTTP 200, content-type text/html; charset=utf-8
https://freakoff.wolfie.gg/wolfie_ -> HTTP 200, content-type text/html; charset=utf-8
```

Both responses include:

```text
cache-control: private, no-cache, no-store, max-age=0, must-revalidate
x-powered-by: Next.js
```

## Latest known database backup

```text
/srv/vps-data/db-dumps/insforge-freakoff_prod-20260629T032502Z.dump
```

Timestamp from VPS listing:

```text
2026-06-29 03:25 UTC
```

## Restore command shape

Use only after explicit confirmation. Replace target DB if restoring to a scratch database first.

```bash
pg_restore --clean --if-exists --no-owner --dbname "$DATABASE_URL" /srv/vps-data/db-dumps/insforge-freakoff_prod-20260629T032502Z.dump
```

## Edge rollback command shape

If a future edge cutover points `freakoff.wolfie.gg` at K3s and fails, restore the Docker upstream block above and reload edge Caddy with validation first. The existing managed route deployer already follows backup, validate, write, reload/restart semantics.

Manual emergency rollback shape:

```bash
ssh hostinger-devbox-ts 'sudo cp /srv/agent-webhook-hub/Caddyfile.bak.<backup-id> /srv/agent-webhook-hub/Caddyfile && docker restart agent-webhook-hub-caddy-1'
```

Preferred rollback once a managed Freak Off fragment exists:

```bash
./scripts/deploy-caddy-k8s-health.sh
```
