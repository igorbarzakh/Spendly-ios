#!/bin/sh
set -eu

umask 077
DEPLOY_DIR=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
COMPOSE_FILE=${COMPOSE_FILE:-"$DEPLOY_DIR/compose.yaml"}
ENV_FILE=${ENV_FILE:-"$DEPLOY_DIR/.env"}

test -f "$ENV_FILE" || { echo "environment file not found: $ENV_FILE" >&2; exit 1; }
set -a
. "$ENV_FILE"
set +a

: "${POSTGRES_DB:?POSTGRES_DB is required}"
: "${POSTGRES_USER:?POSTGRES_USER is required}"
: "${AGE_RECIPIENT:?AGE_RECIPIENT is required}"
BACKUP_DIR=${BACKUP_DIR:-/var/backups/spendly}
BACKUP_RETENTION_DAYS=${BACKUP_RETENTION_DAYS:-14}

case "$BACKUP_DIR" in
    /*) ;;
    *) echo "BACKUP_DIR must be an absolute dedicated directory: $BACKUP_DIR" >&2; exit 1 ;;
esac
case "$BACKUP_DIR/" in
    */../*|*/./*|*//*) echo "unsafe BACKUP_DIR: $BACKUP_DIR" >&2; exit 1 ;;
esac
case "$BACKUP_RETENTION_DAYS" in
    *[!0-9]*|"") echo "BACKUP_RETENTION_DAYS must be a non-negative integer" >&2; exit 1 ;;
esac

command -v age >/dev/null 2>&1 || { echo "age is required" >&2; exit 1; }
command -v sha256sum >/dev/null 2>&1 || { echo "sha256sum is required" >&2; exit 1; }
command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
command -v flock >/dev/null 2>&1 || { echo "flock is required" >&2; exit 1; }

compose() {
    docker compose --env-file "$ENV_FILE" -f "$COMPOSE_FILE" "$@"
}

marker_text="Spendly encrypted backup directory"
marker_path="$BACKUP_DIR/.spendly-backup-directory"
if test -e "$BACKUP_DIR" || test -L "$BACKUP_DIR"; then
    test -d "$BACKUP_DIR" && test ! -L "$BACKUP_DIR" || {
        echo "BACKUP_DIR must be a real directory, not a symlink: $BACKUP_DIR" >&2
        exit 1
    }
    test -f "$marker_path" && test ! -L "$marker_path" &&
        test "$(cat "$marker_path")" = "$marker_text" || {
        echo "existing BACKUP_DIR is not initialized for Spendly backups: $BACKUP_DIR" >&2
        exit 1
    }
else
    mkdir -p "$BACKUP_DIR"
    test ! -L "$BACKUP_DIR" || { echo "BACKUP_DIR resolved to a symlink" >&2; exit 1; }
    chmod 700 "$BACKUP_DIR"
    printf '%s\n' "$marker_text" >"$marker_path"
fi

lock_file="$BACKUP_DIR/.backup.lock"
test ! -L "$lock_file" || { echo "backup lock must not be a symlink" >&2; exit 1; }
if test -e "$lock_file" && test ! -f "$lock_file"; then
    echo "backup lock must be a regular file: $lock_file" >&2
    exit 1
fi
exec 9>"$lock_file"
if ! flock -n 9; then
    echo "another Spendly backup is already running" >&2
    exit 1
fi

timestamp=$(date -u +%Y%m%dT%H%M%SZ)
archive_name="spendly-${timestamp}.dump.age"
sequence=0
while test -e "$BACKUP_DIR/$archive_name" || test -e "$BACKUP_DIR/$archive_name.sha256"; do
    sequence=$((sequence + 1))
    archive_name="spendly-${timestamp}-${sequence}.dump.age"
done
archive_path="$BACKUP_DIR/$archive_name"
raw_path="$BACKUP_DIR/.spendly-${timestamp}.$$.dump"
encrypted_path="$archive_path.tmp.$$"
checksum_path="$archive_path.sha256"
cleanup() {
    rm -f "$raw_path" "$encrypted_path" "$checksum_path.tmp"
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM

compose exec -T postgres pg_dump \
    --username "$POSTGRES_USER" \
    --dbname "$POSTGRES_DB" \
    --format=custom \
    --no-owner \
    --no-privileges >"$raw_path"

age --recipient "$AGE_RECIPIENT" --output "$encrypted_path" "$raw_path"
rm -f "$raw_path"
mv "$encrypted_path" "$archive_path"
(
    cd "$BACKUP_DIR"
    sha256sum "$archive_name" >"$archive_name.sha256.tmp"
    mv "$archive_name.sha256.tmp" "$archive_name.sha256"
)

for backup_candidate in "$BACKUP_DIR"/spendly-*.dump.age; do
    test -f "$backup_candidate" || continue
    if test -n "$(find "$backup_candidate" -mtime "+$BACKUP_RETENTION_DAYS" -print)"; then
        rm -f "$backup_candidate" "$backup_candidate.sha256"
    fi
done

echo "$archive_path"
