#!/bin/sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname "$0")/../.." && pwd)
COMPOSE_FILE="$ROOT_DIR/deploy/compose.yaml"
ENV_FILE="$ROOT_DIR/deploy/.env.example"
CONFIG_JSON=$(mktemp "${TMPDIR:-/tmp}/spendly-compose.XXXXXX")
EMPTY_ENV=$(mktemp "${TMPDIR:-/tmp}/spendly-empty-env.XXXXXX")
cleanup() {
    rm -f "$CONFIG_JSON" "$EMPTY_ENV"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

for file in \
    "$ROOT_DIR/backend/Dockerfile" \
    "$COMPOSE_FILE" \
    "$ROOT_DIR/deploy/Caddyfile" \
    "$ENV_FILE" \
    "$ROOT_DIR/deploy/backup/backup.sh" \
    "$ROOT_DIR/deploy/backup/restore.sh" \
    "$ROOT_DIR/deploy/tests/smoke.sh" \
    "$ROOT_DIR/deploy/tests/restore-drill.sh"
do
    test -f "$file" || { echo "missing required file: $file" >&2; exit 1; }
done

docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" config --format json >"$CONFIG_JSON"

jq -e '(.services.api.ports // []) | length == 0' "$CONFIG_JSON" >/dev/null
jq -e '(.services.postgres.ports // []) | length == 0' "$CONFIG_JSON" >/dev/null
jq -e '.services.api.read_only == true' "$CONFIG_JSON" >/dev/null
jq -e '[.services.caddy.ports[].target] | sort | unique == [80, 443]' "$CONFIG_JSON" >/dev/null
jq -e '[.services.api, .services.postgres, .services.caddy] | map(has("healthcheck")) | all' "$CONFIG_JSON" >/dev/null
jq -e '.services.postgres.volumes | any(.target == "/var/lib/postgresql")' "$CONFIG_JSON" >/dev/null
jq -e '.services.caddy.volumes | any(.target == "/data") and any(.target == "/config")' "$CONFIG_JSON" >/dev/null
jq -e '.networks.backend.internal == true' "$CONFIG_JSON" >/dev/null
jq -e '.services.postgres.image | contains("@sha256:")' "$CONFIG_JSON" >/dev/null
jq -e '.services.caddy.image | contains("@sha256:")' "$CONFIG_JSON" >/dev/null
jq -e '[.services.api, .services.postgres, .services.caddy] |
    map(.logging.options["max-size"] == "10m" and .logging.options["max-file"] == "3") | all' \
    "$CONFIG_JSON" >/dev/null

awk '
    $1 == "FROM" && $2 != "scratch" && $2 !~ /@sha256:/ { exit 1 }
' "$ROOT_DIR/backend/Dockerfile" || {
    echo "every non-scratch Dockerfile base image must be pinned by digest" >&2
    exit 1
}

grep -q 'request_body' "$ROOT_DIR/deploy/Caddyfile"
grep -q 'Authorization delete' "$ROOT_DIR/deploy/Caddyfile"
grep -q 'Cookie delete' "$ROOT_DIR/deploy/Caddyfile"
test -f "$ROOT_DIR/backend/.dockerignore"
grep -q '^\.env$' "$ROOT_DIR/backend/.dockerignore"
grep -q 'flock -n 9' "$ROOT_DIR/deploy/backup/backup.sh"
if grep -q 'log_credentials' "$ROOT_DIR/deploy/Caddyfile"; then
    echo "Caddy must not log credentials" >&2
    exit 1
fi

sh -n "$ROOT_DIR/deploy/backup/backup.sh"
sh -n "$ROOT_DIR/deploy/backup/restore.sh"
sh -n "$ROOT_DIR/deploy/tests/smoke.sh"
sh -n "$ROOT_DIR/deploy/tests/restore-drill.sh"

if output=$(POSTGRES_DB=spendly RESTORE_TARGET_DATABASE=spendly \
    sh "$ROOT_DIR/deploy/backup/restore.sh" /tmp/not-a-backup.dump.age 2>&1); then
    echo "restore accepted the production database name" >&2
    exit 1
fi
echo "$output" | grep -qi 'refus'

unsafe_backup_dir=$(mktemp -d "/tmp/spendly-unsafe-backup.XXXXXX")
if output=$(ENV_FILE="$EMPTY_ENV" POSTGRES_DB=spendly POSTGRES_USER=spendly \
    AGE_RECIPIENT=age1unused BACKUP_DIR="$unsafe_backup_dir" \
    sh "$ROOT_DIR/deploy/backup/backup.sh" 2>&1); then
    echo "backup accepted an existing unmarked directory" >&2
    rmdir "$unsafe_backup_dir"
    exit 1
fi
echo "$output" | grep -qi 'not initialized'
rmdir "$unsafe_backup_dir"

echo "deployment config checks passed"
