# Spendly production deployment

Spendly runs as a single Docker Compose project on the VDS:

```text
Internet -> Caddy :80/:443 -> Go API :8080 -> PostgreSQL :5432
```

Only Caddy publishes host ports. The API and PostgreSQL have no host port mappings. PostgreSQL is attached only to the internal `backend` network. The API also uses the `egress` network because Google and Apple JWKS verification requires outbound HTTPS.

## VDS prerequisites

- Ubuntu with current security updates.
- Docker Engine with the Compose plugin.
- `curl` and `jq` for deployment smoke/config checks; `age` and `flock` (from `util-linux`) for encrypted backups.
- DNS `A` record for `api.spendly.app` pointing to the VDS IPv4 address.
- Inbound firewall rules for SSH, TCP 80, TCP 443 and UDP 443 only.
- At least 1 GB RAM. On a 1 GB VDS, configure a small swap file and monitor memory pressure.

Clone the repository to a directory owned by the deployment user. Run all commands below from the repository root.

## Configure secrets

```sh
cp deploy/.env.example deploy/.env
chmod 600 deploy/.env
```

Replace every placeholder in `deploy/.env`. Generate a database password and a raw Ed25519 private key with:

```sh
openssl rand -base64 36
openssl rand 64 | base64 -w0 | tr -d '='
```

`DATABASE_URL` must contain the URL-encoded database password. `POSTGRES_PASSWORD` contains the original password. Never commit `deploy/.env`.

Set `SPENDLY_API_TAG` to an immutable release identifier such as a Git commit SHA. Keeping the previous tag locally makes rollback predictable.

## First deployment

Validate configuration before changing running services:

```sh
sh deploy/tests/config.sh
docker compose --env-file deploy/.env -f deploy/compose.yaml config --quiet
```

Build both production targets:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml --profile tools build api migrate
```

Apply migrations as a one-off container before starting the new API:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml --profile tools run --rm migrate up
```

Start the three long-running services:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d postgres api caddy
docker compose --env-file deploy/.env -f deploy/compose.yaml ps
sh deploy/tests/smoke.sh
```

Caddy obtains and renews the TLS certificate automatically. DNS must already resolve to the VDS, and ports 80/443 must be reachable before Caddy starts.

## Routine deployment

1. Create and verify a fresh encrypted backup.
2. Pull the desired Git revision.
3. Set a new immutable `SPENDLY_API_TAG` in `deploy/.env`.
4. Build `api` and `migrate`.
5. Run `migrate up`.
6. Recreate `api` and `caddy`.
7. Run the smoke test and inspect service health/logs.

```sh
deploy/backup/backup.sh
docker compose --env-file deploy/.env -f deploy/compose.yaml --profile tools build api migrate
docker compose --env-file deploy/.env -f deploy/compose.yaml --profile tools run --rm migrate up
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d api caddy
sh deploy/tests/smoke.sh
```

View sanitized logs with:

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml logs --tail=200 api caddy postgres
```

Caddy redacts credentials by default, and the Caddyfile explicitly removes `Authorization` and `Cookie` fields from access logs. Do not enable `log_credentials`.

## Rollback

Application rollback is performed by restoring the previous `SPENDLY_API_TAG`, rebuilding/re-pulling that image, and recreating `api`. Do not run a down migration automatically: schema rollback is a separately reviewed operation and may destroy data.

```sh
docker compose --env-file deploy/.env -f deploy/compose.yaml up -d --no-deps api
sh deploy/tests/smoke.sh
```

If a migration caused a data problem, stop writes and follow the backup runbook. Restore into a separate database first; the restore script intentionally refuses the production database name.

## Operational checks

- `https://api.spendly.app/health/live` confirms the API process is alive.
- `https://api.spendly.app/health/ready` confirms PostgreSQL is reachable.
- `docker compose ps` must report `postgres`, `api`, and `caddy` as healthy.
- Monitor disk usage closely: the VDS has only 10 GB. Copy encrypted backups off-server and prune unused images with a reviewed maintenance procedure.
- Install OS and Docker security updates regularly. Reboot only after confirming a recent off-server backup.
