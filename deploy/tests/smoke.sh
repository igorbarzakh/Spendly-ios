#!/bin/sh
set -eu

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-"$DEPLOY_DIR/compose.yaml"}
ENV_FILE=${ENV_FILE:-"$DEPLOY_DIR/.env"}
test -f "$ENV_FILE" || { echo "environment file not found: $ENV_FILE" >&2; exit 1; }

set -a
. "$ENV_FILE"
set +a
: "${SPENDLY_DOMAIN:?SPENDLY_DOMAIN is required}"
BASE_URL=${SPENDLY_SMOKE_BASE_URL:-"https://$SPENDLY_DOMAIN"}

compose() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

compose ps --format json | jq -s -e '
    [.[] | select(.Service == "api" or .Service == "postgres") |
     .Publishers[]? | select(.PublishedPort != 0)] | length == 0
' >/dev/null || {
    echo "API or PostgreSQL unexpectedly publishes a host port" >&2
    exit 1
}

if test "${SPENDLY_SMOKE_INSECURE:-0}" = "1"; then
    curl -kfsS --retry 15 --retry-all-errors --retry-delay 2 "$BASE_URL/health/live" >/dev/null
    curl -kfsS --retry 15 --retry-all-errors --retry-delay 2 "$BASE_URL/health/ready" >/dev/null
    headers=$(curl -kfsSI "$BASE_URL/health/live")
else
    curl -fsS --retry 15 --retry-all-errors --retry-delay 2 "$BASE_URL/health/live" >/dev/null
    curl -fsS --retry 15 --retry-all-errors --retry-delay 2 "$BASE_URL/health/ready" >/dev/null
    headers=$(curl -fsSI "$BASE_URL/health/live")
fi

echo "$headers" | grep -qi '^strict-transport-security:'
echo "$headers" | grep -qi '^x-content-type-options: nosniff'
echo "$headers" | grep -qi '^x-frame-options: DENY'
compose ps
echo "production smoke checks passed"
