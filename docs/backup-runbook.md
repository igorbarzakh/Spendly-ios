# Spendly backup and restore runbook

Backups are PostgreSQL custom-format dumps encrypted with `age`. A backup is considered usable only after its checksum is verified and it has been restored into a disposable database.

## One-time setup

Install `age` and create a dedicated backup identity on the VDS:

```sh
sudo apt-get update
sudo apt-get install -y age
sudo install -d -m 700 /root/.config/age
sudo age-keygen -o /root/.config/age/spendly-backup-key.txt
sudo chmod 600 /root/.config/age/spendly-backup-key.txt
```

Store an offline copy of the identity file in a secure password manager or encrypted removable storage. Losing it makes every backup unrecoverable. Put the printed public recipient into `AGE_RECIPIENT` and the identity path into `AGE_IDENTITY_FILE` in `deploy/.env`.

The default backup directory is `/var/backups/spendly`, mode `0700`. On first use the script creates it with a Spendly marker; it refuses existing unmarked directories and symlinks so a bad environment value cannot change permissions or run retention in an arbitrary location. Backups are serialized with a directory lock. The default local retention is 14 days. Because the VDS disk is small, transfer every `.dump.age` and matching `.sha256` file to independent off-server storage.

## Create a backup

```sh
sudo ENV_FILE=/path/to/spendly-ios/deploy/.env \
  /path/to/spendly-ios/deploy/backup/backup.sh
```

The script:

1. Runs `pg_dump --format=custom --no-owner --no-privileges` inside PostgreSQL.
2. Writes the temporary plaintext dump with owner-only permissions and removes it on exit.
3. Encrypts the dump to the configured `age` recipient.
4. Writes a SHA-256 checksum for the encrypted archive.
5. Removes encrypted archives and checksums older than `BACKUP_RETENTION_DAYS`.

Successful output is the absolute encrypted archive path. Copy both files off the VDS:

```text
spendly-YYYYMMDDTHHMMSSZ.dump.age
spendly-YYYYMMDDTHHMMSSZ.dump.age.sha256
```

## Daily schedule

Example `/etc/cron.d/spendly-backup` entry:

```cron
17 3 * * * root ENV_FILE=/srv/spendly-ios/deploy/.env /srv/spendly-ios/deploy/backup/backup.sh >>/var/log/spendly-backup.log 2>&1
```

Alert on a missing daily archive, a non-zero cron exit, low disk space, or a failed off-server transfer. Retention is not a substitute for off-server storage.

The script holds a non-blocking kernel `flock` for the entire backup. The kernel releases it automatically after a normal exit, signal, process crash, or host reboot. The empty `.backup.lock` file remains by design and must not be replaced with a symlink.

## Restore drill

Run this after initial setup, after PostgreSQL/image upgrades, and at least monthly:

```sh
sudo ENV_FILE=/srv/spendly-ios/deploy/.env \
  /srv/spendly-ios/deploy/tests/restore-drill.sh
```

The drill creates a uniquely named disposable database, creates a fresh encrypted backup, restores it with `--exit-on-error --single-transaction`, verifies public tables and `schema_migrations`, and drops the disposable database on exit.

Record the date, archive name, duration and result. A file that has never passed this drill is not a verified backup.

## Manual restore into a disposable database

Create an explicitly named non-production target:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml exec -T postgres \
  createdb --username spendly spendly_restore_test
```

Restore and verify:

```sh
deploy/backup/restore.sh \
  /var/backups/spendly/spendly-YYYYMMDDTHHMMSSZ.dump.age \
  spendly_restore_test
```

The restore script verifies the encrypted archive checksum before decryption. It accepts only simple PostgreSQL identifiers, requires the target database to exist, and refuses any target equal to `POSTGRES_DB`.

## Disaster recovery

Never bypass the production-name guard during routine operation.

1. Stop the API to prevent writes.
2. Provision a new empty database with a non-production name.
3. Restore and run application/read checks against that database.
4. Take a separate copy of the damaged production volume/database.
5. Change `DATABASE_URL` only after the restored database has been reviewed.
6. Start the API, verify readiness, authentication and purchase reads/writes.
7. Preserve the incident archive and document the recovery.

For a total VDS loss, create a new VDS, restore the repository and `age` identity from independent storage, deploy PostgreSQL, copy back the encrypted archive/checksum, and follow the same separate-database procedure.
