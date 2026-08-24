#!/bin/sh
set -eu

DEPLOY_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
ENV_FILE=${ENV_FILE:-"$DEPLOY_DIR/.env"}
COMPOSE_FILE=${COMPOSE_FILE:-"$DEPLOY_DIR/compose.yaml"}
test -f "$ENV_FILE" || { echo "environment file not found: $ENV_FILE" >&2; exit 1; }

set -a
. "$ENV_FILE"
set +a
: "${POSTGRES_USER:?POSTGRES_USER is required}"

compose() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

target="spendly_restore_drill_$(date -u +%Y%m%d%H%M%S)"
case "$target" in *[!a-zA-Z0-9_]*) exit 1 ;; esac
cleanup() {
    compose exec -T postgres dropdb --username "$POSTGRES_USER" --if-exists "$target" >/dev/null 2>&1 || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

backup_file=$(ENV_FILE="$ENV_FILE" COMPOSE_FILE="$COMPOSE_FILE" "$DEPLOY_DIR/backup/backup.sh")
compose exec -T postgres createdb --username "$POSTGRES_USER" "$target"
ENV_FILE="$ENV_FILE" COMPOSE_FILE="$COMPOSE_FILE" \
    "$DEPLOY_DIR/backup/restore.sh" "$backup_file" "$target"

table_count=$(compose exec -T postgres psql \
    --username "$POSTGRES_USER" \
    --dbname "$target" \
    --tuples-only \
    --no-align \
    --command "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")
test "$table_count" -gt 0
compose exec -T postgres psql --username "$POSTGRES_USER" --dbname "$target" \
    --tuples-only --no-align --command "SELECT version FROM schema_migrations ORDER BY version DESC LIMIT 1" |
    grep -Eq '^[0-9]+$'

echo "restore drill passed using disposable database $target"
