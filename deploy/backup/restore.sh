#!/bin/sh
set -eu

umask 077
DEPLOY_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-"$DEPLOY_DIR/compose.yaml"}
ENV_FILE=${ENV_FILE:-"$DEPLOY_DIR/.env"}
BACKUP_FILE=${1:-}
TARGET_DATABASE=${2:-${RESTORE_TARGET_DATABASE:-}}

test -n "$TARGET_DATABASE" || {
    echo "usage: restore.sh BACKUP_FILE TARGET_DATABASE" >&2
    exit 1
}
case "$TARGET_DATABASE" in
    *[!a-zA-Z0-9_]*) echo "target database must be a simple PostgreSQL identifier" >&2; exit 1 ;;
esac

if test -f "$ENV_FILE"; then
    set -a
    . "$ENV_FILE"
    set +a
fi
: "${POSTGRES_DB:?POSTGRES_DB is required}"

if test "$TARGET_DATABASE" = "$POSTGRES_DB"; then
    echo "refusing to restore into production database: $POSTGRES_DB" >&2
    exit 1
fi
: "${POSTGRES_USER:?POSTGRES_USER is required}"

test -n "$BACKUP_FILE" || { echo "backup file is required" >&2; exit 1; }
test -f "$BACKUP_FILE" || { echo "backup file not found: $BACKUP_FILE" >&2; exit 1; }
test -f "$BACKUP_FILE.sha256" || { echo "checksum file not found: $BACKUP_FILE.sha256" >&2; exit 1; }
: "${AGE_IDENTITY_FILE:?AGE_IDENTITY_FILE is required}"
test -f "$AGE_IDENTITY_FILE" || { echo "age identity not found: $AGE_IDENTITY_FILE" >&2; exit 1; }

command -v age >/dev/null 2>&1 || { echo "age is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }

compose() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

backup_dir=$(CDPATH= cd -- "$(dirname "$BACKUP_FILE")" && pwd)
backup_name=$(basename "$BACKUP_FILE")
(
    cd "$backup_dir"
    sha256sum --check "$backup_name.sha256"
)

raw_path="${TMPDIR:-/tmp}/spendly-restore.$$.dump"
cleanup() {
    rm -f "$raw_path"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
age --decrypt --identity "$AGE_IDENTITY_FILE" --output "$raw_path" "$BACKUP_FILE"

exists=$(compose exec -T postgres psql \
    --username "$POSTGRES_USER" \
    --dbname postgres \
    --tuples-only \
    --no-align \
    --command "SELECT 1 FROM pg_database WHERE datname = '$TARGET_DATABASE'")
test "$exists" = "1" || {
    echo "target database does not exist: $TARGET_DATABASE" >&2
    exit 1
}

compose exec -T postgres pg_restore \
    --username "$POSTGRES_USER" \
    --dbname "$TARGET_DATABASE" \
    --clean \
    --if-exists \
    --no-owner \
    --no-privileges \
    --exit-on-error \
    --single-transaction <"$raw_path"

echo "restore completed into $TARGET_DATABASE"
