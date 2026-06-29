#!/usr/bin/env bash
set -euo pipefail

REMOTE_HOST="${REMOTE_HOST:-hostinger-devbox-ts}"
REMOTE_DIR="${REMOTE_DIR:-/tmp/wolfie-platform-lab}"
IMAGE_NAME="${IMAGE_NAME:-wolfie-health-api:0.1.0}"
NAMESPACE="${NAMESPACE:-platform-lab}"
DEPLOYMENT="${DEPLOYMENT:-wolfie-health-api}"

rsync -az --delete \
  --exclude node_modules \
  --exclude .DS_Store \
  ./ "${REMOTE_HOST}:${REMOTE_DIR}/"

ssh "${REMOTE_HOST}" "docker build -t '${IMAGE_NAME}' '${REMOTE_DIR}'"
ssh "${REMOTE_HOST}" "docker save '${IMAGE_NAME}' | sudo k3s ctr images import -"
ssh "${REMOTE_HOST}" "sudo k3s kubectl apply -f '${REMOTE_DIR}/k8s/health-api.yaml'"
ssh "${REMOTE_HOST}" "sudo k3s kubectl -n '${NAMESPACE}' rollout status deployment/'${DEPLOYMENT}'"
ssh "${REMOTE_HOST}" "sudo k3s kubectl -n '${NAMESPACE}' run curl-health --rm -i --restart=Never --image=curlimages/curl:8.12.1 -- http://'${DEPLOYMENT}'/healthz"
