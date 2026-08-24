# Spendly

Spendly is a production-oriented iOS 17+ application backed by a self-hosted Go REST API and PostgreSQL. This repository is the monorepo for the SwiftUI client, Go backend, database migrations, Docker/Caddy deployment, tests, and operational documentation.

## Toolchain

- Xcode 26.6 (build 17F113)
- Apple Swift 6.3.3
- Go 1.27.0
- PostgreSQL 18.6
- Docker 29.5.2
- XcodeGen 2.46.0
- iOS Simulator Runtime 26.5

The machine currently selects Command Line Tools globally. Until an administrator runs `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer`, prefix Xcode commands with:

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
```

## Generate the Xcode project

```bash
xcodegen generate
```

## Backend checks

```bash
docker compose -f deploy/compose.test.yaml up -d postgres
cd backend
TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./...
go vet ./...
```

## Deployment

Production runs on one Compose host: Caddy terminates TLS on `80/443`, the Go API listens only on the internal Docker network, and PostgreSQL is not published externally. See `docs/deployment.md` and `docs/backup-runbook.md`.

No production credentials belong in this repository. Client traffic must use `https://api.spendly.app`; direct database access from iOS is prohibited.
