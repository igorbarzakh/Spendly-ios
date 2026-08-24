# Spendly Go Backend Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Заменить Supabase на self-hosted Go API и PostgreSQL, подключить к нему iOS-клиент и развернуть API, БД и Caddy на одном VDS.

**Architecture:** Один Go-процесс разделён на feature-пакеты и предоставляет versioned REST API. PostgreSQL хранит данные и сессии, Caddy завершает TLS, а SwiftData остаётся локальным кэшем и очередью мутаций iOS.

**Tech Stack:** Go 1.27, standard `net/http`, pgx v5, PostgreSQL 18, Swift 6/SwiftUI/SwiftData, XCTest, Docker Compose, Caddy, GitHub Actions.

---

Перед выполнением прочитать `docs/plans/2026-08-24-spendly-go-backend-design.md`. Все команды запускаются из корня репозитория. Каждый task завершается отдельным коммитом; не удалять Supabase до прохождения iOS contract tests и compose smoke test.

## Phase 1. API foundation and database

### Task 1: Создать Go workspace и безопасный HTTP lifecycle

**Files:**
- Create: `backend/go.mod`
- Create: `backend/cmd/api/main.go`
- Create: `backend/internal/config/config.go`
- Create: `backend/internal/config/config_test.go`
- Create: `backend/internal/httpapi/server.go`
- Create: `backend/internal/httpapi/server_test.go`
- Create: `backend/internal/observability/log.go`
- Create: `backend/.env.example`

**Step 1: Написать failing tests конфигурации**

Проверить обязательные `DATABASE_URL`, `TOKEN_SIGNING_KEY`, `APPLE_CLIENT_ID`, `GOOGLE_CLIENT_ID`, положительные HTTP timeouts и запрет логирования секретов.

```go
func TestLoadRejectsMissingDatabaseURL(t *testing.T) {
    t.Setenv("DATABASE_URL", "")
    _, err := config.Load()
    if !errors.Is(err, config.ErrMissingDatabaseURL) {
        t.Fatalf("expected missing database URL, got %v", err)
    }
}
```

**Step 2: Запустить тест и подтвердить FAIL**

Run: `cd backend && go test ./internal/config ./internal/httpapi`

Expected: FAIL — пакеты ещё не существуют.

**Step 3: Реализовать минимальный сервер**

Использовать `http.Server` с явными `ReadHeaderTimeout`, `ReadTimeout`, `WriteTimeout`, `IdleTimeout`, лимитом request body и graceful shutdown по `SIGINT/SIGTERM`. Добавить:

```text
GET /health/live  -> 200 {"status":"ok"}
GET /health/ready -> 503, пока database probe не подключён
```

Логи — JSON через `log/slog`; middleware добавляет/возвращает `X-Request-ID`.

**Step 4: Проверить**

Run: `cd backend && gofmt -w . && go test ./... && go vet ./...`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend
git commit -m "chore: scaffold Spendly Go API"
```

### Task 2: Перенести схему в обычные PostgreSQL migrations

**Files:**
- Create: `backend/cmd/migrate/main.go`
- Create: `backend/internal/postgres/pool.go`
- Create: `backend/internal/postgres/migrate.go`
- Create: `backend/internal/postgres/migrate_test.go`
- Create: `backend/migrations/0001_initial.up.sql`
- Create: `backend/migrations/0001_initial.down.sql`
- Create: `backend/tests/postgres.sh`
- Create: `deploy/compose.test.yaml`

**Step 1: Поднять тестовую БД и написать failing migration test**

`migrate_test.go` применяет миграцию к пустой базе и проверяет таблицы `schema_migrations`, `users`, `user_identities`, `user_sessions`, `profiles`, `groups`, `group_members`, `group_invitations`, `purchases`, `purchase_items`, `idempotency_keys`.

Run: `docker compose -f deploy/compose.test.yaml up -d postgres`

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test ./internal/postgres -run TestMigrateFreshDatabase -v`

Expected: FAIL — migration runner/schema отсутствуют.

**Step 2: Реализовать migration runner**

Использовать `//go:embed migrations/*.sql`, PostgreSQL advisory lock и транзакцию на миграцию. Команды:

```text
go run ./cmd/migrate up
go run ./cmd/migrate status
```

Не выполнять migrations автоматически при старте API.

**Step 3: Перенести схему**

Взять constraints и indexes из `supabase/migrations/0001_initial_schema.sql`, заменить ссылки `auth.users` на `users`, добавить auth/session/idempotency tables и запретить пустые provider subjects. Refresh token хранить как `bytea token_hash`, не как открытый token.

**Step 4: Проверить clean up/down/up**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test ./internal/postgres -v`

Expected: PASS; повторный `up` ничего не меняет.

**Step 5: Commit**

```bash
git add backend deploy/compose.test.yaml
git commit -m "feat: add PostgreSQL schema and migrations"
```

### Task 3: Добавить transaction boundary и repository test harness

**Files:**
- Create: `backend/internal/postgres/db.go`
- Create: `backend/internal/postgres/testdb_test.go`
- Create: `backend/internal/postgres/transaction_test.go`
- Modify: `backend/internal/httpapi/server.go`
- Modify: `backend/cmd/api/main.go`

**Step 1: Написать failing integration tests**

Проверить rollback при ошибке callback, commit при успехе, отмену query по context и readiness `200/503` в зависимости от `Ping`.

**Step 2: Реализовать DB abstraction**

Создать узкие интерфейсы `DBTX`, `Transactor` и pgxpool implementation. Не добавлять универсальный ORM или generic repository.

**Step 3: Подключить readiness**

`/health/ready` выполняет bounded database ping; ошибка возвращает только стабильный публичный код, без DSN и текста драйвера.

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./...`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend
git commit -m "feat: add transactional PostgreSQL access"
```

## Phase 2. Authentication

### Task 4: Реализовать внутренние access/refresh sessions

**Files:**
- Create: `backend/internal/auth/model.go`
- Create: `backend/internal/auth/token.go`
- Create: `backend/internal/auth/token_test.go`
- Create: `backend/internal/auth/session_repository.go`
- Create: `backend/internal/auth/session_repository_test.go`
- Create: `backend/internal/auth/service.go`
- Create: `backend/internal/auth/service_test.go`

**Step 1: Написать failing tests**

Покрыть expiry/audience/signature access token, 32-byte random refresh token, SHA-256 hash at rest, rotation, reuse detection, logout и logout-all. Random opaque token не хэшировать медленным password KDF.

```go
func TestRefreshRotationRevokesFamilyOnReuse(t *testing.T) {
    first := issueSession(t)
    second := rotate(t, first.RefreshToken)
    requireReuseDetected(t, first.RefreshToken)
    requireRevoked(t, second.RefreshToken)
}
```

**Step 2: Реализовать access tokens**

Подписывать минимальные claims (`sub`, `sid`, `iss`, `aud`, `iat`, `exp`) асимметричным ключом. Parser принимает только ожидаемый algorithm, issuer и audience; ключи загружаются из environment/secret file.

**Step 3: Реализовать refresh rotation**

При rotation блокировать session row `FOR UPDATE`, помечать старый token использованным и создавать следующий в той же family. Повтор использованного token отзывает всю family.

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./internal/auth`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/internal/auth
git commit -m "feat: add secure API sessions"
```

### Task 5: Проверять Google и Apple identity tokens

**Files:**
- Create: `backend/internal/auth/provider.go`
- Create: `backend/internal/auth/oidc_verifier.go`
- Create: `backend/internal/auth/oidc_verifier_test.go`
- Create: `backend/internal/auth/testdata/google-jwks.json`
- Create: `backend/internal/auth/testdata/apple-jwks.json`
- Modify: `backend/internal/config/config.go`

**Step 1: Написать failing verifier tests**

Для обоих providers проверить валидный token, неверные signature/issuer/audience/expiry/nonce, отсутствующий `sub`, неизвестный `kid`, обновление и TTL JWKS cache. Fixtures генерировать тестовым ключом; не коммитить реальные tokens.

**Step 2: Реализовать provider-neutral interface**

```go
type Identity struct {
    Provider Provider
    Subject  string
    Email    string
    Name     string
}

type IdentityVerifier interface {
    Verify(ctx context.Context, rawToken, nonce string) (Identity, error)
}
```

Google и Apple получают отдельные issuer, audience и JWKS URL из immutable config. HTTP client имеет timeout; cache защищён от stampede.

**Step 3: Запретить опасные fallback**

Не принимать email, имя или непроверенный JWT payload как identity. Не продолжать регистрацию при недоступном JWKS и отсутствии подходящего свежего cached key.

**Step 4: Проверить**

Run: `cd backend && go test -race ./internal/auth -run 'TestOIDC|TestJWKS' -v`

Expected: PASS без сетевых запросов в unit tests.

**Step 5: Commit**

```bash
git add backend/internal/auth backend/internal/config
git commit -m "feat: verify Apple and Google identities"
```

### Task 6: Добавить auto-registration и auth HTTP endpoints

**Files:**
- Create: `backend/internal/auth/identity_repository.go`
- Create: `backend/internal/auth/identity_repository_test.go`
- Create: `backend/internal/httpapi/auth_handler.go`
- Create: `backend/internal/httpapi/auth_handler_test.go`
- Create: `backend/internal/httpapi/auth_middleware.go`
- Create: `backend/internal/httpapi/auth_middleware_test.go`
- Create: `docs/api/openapi.yaml`

**Step 1: Написать failing tests**

Проверить:

- первый `(provider, sub)` создаёт ровно одного `users`/`profiles`/`user_identities`;
- повторный вход возвращает тот же `user_id`;
- конкурентные первые входы не создают дубль;
- одинаковый `sub` разных providers создаёт разных пользователей;
- неверный token не пишет в БД;
- refresh/logout требуют корректный token.

**Step 2: Реализовать transactional find-or-create**

Опора только на `UNIQUE(provider, provider_subject)` и обработку unique conflict. Email/name обновлять как profile hints, не использовать для поиска или merge.

**Step 3: Реализовать routes**

```text
POST /v1/auth/google
POST /v1/auth/apple
POST /v1/auth/refresh
POST /v1/auth/logout
POST /v1/auth/logout-all
GET  /v1/me
```

Добавить JSON envelope, request ID, uniform unauthorized response и body limit. Обновить OpenAPI request/response/error schemas.

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./internal/auth ./internal/httpapi`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend docs/api/openapi.yaml
git commit -m "feat: add Apple and Google sign-in API"
```

## Phase 3. Spendly business API

### Task 7: Реализовать purchases application service

**Files:**
- Create: `backend/internal/purchases/model.go`
- Create: `backend/internal/purchases/service.go`
- Create: `backend/internal/purchases/service_test.go`
- Create: `backend/internal/purchases/repository.go`
- Create: `backend/internal/purchases/repository_test.go`
- Create: `backend/internal/httpapi/purchases_handler.go`
- Create: `backend/internal/httpapi/purchases_handler_test.go`
- Modify: `docs/api/openapi.yaml`

**Step 1: Написать failing domain/service tests**

Покрыть quick/detailed invariants, minor units overflow, derived detailed total, personal/group visibility, permission matrix, idempotent create, expected-version conflict и atomic replacement of items.

**Step 2: Реализовать commands и queries**

Repository принимает внутренний authenticated `UserID`; `owner_id` из JSON игнорировать/запрещать. Detailed purchase и items записывать одной транзакцией. Delete — soft delete с version check.

**Step 3: Добавить HTTP endpoints**

```text
GET    /v1/purchases?context=&from=&to=&cursor=
POST   /v1/purchases
PUT    /v1/purchases/{id}
DELETE /v1/purchases/{id}
```

`Idempotency-Key` обязателен для POST. Conflict возвращает `409 version_conflict`, повтор с тем же key и тем же payload — исходный response, с другим payload — `409 idempotency_conflict`.

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./internal/purchases ./internal/httpapi`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/internal/purchases backend/internal/httpapi docs/api/openapi.yaml
git commit -m "feat: add purchases API"
```

### Task 8: Реализовать groups и invitations

**Files:**
- Create: `backend/internal/groups/model.go`
- Create: `backend/internal/groups/service.go`
- Create: `backend/internal/groups/service_test.go`
- Create: `backend/internal/groups/repository.go`
- Create: `backend/internal/groups/repository_test.go`
- Create: `backend/internal/httpapi/groups_handler.go`
- Create: `backend/internal/httpapi/groups_handler_test.go`
- Modify: `docs/api/openapi.yaml`

**Step 1: Написать failing tests permissions matrix**

Проверить auto owner membership, member/manager/owner права, архивирование, невозможность удалить/понизить владельца, invitation expiry/revocation/single-use и запрет вступления дважды.

**Step 2: Реализовать service/repository**

Открытый invitation token генерировать из 32 random bytes, возвращать один раз и хранить только SHA-256 hash. Accept выполняет lock invitation и insert membership в одной транзакции.

**Step 3: Добавить routes**

```text
GET/POST       /v1/groups
GET/PATCH      /v1/groups/{id}
GET/PATCH      /v1/groups/{id}/members/{userID}
POST           /v1/groups/{id}/invitations
POST           /v1/group-invitations/{token}/accept
DELETE         /v1/groups/{id}/invitations/{invitationID}
```

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./internal/groups ./internal/httpapi`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/internal/groups backend/internal/httpapi docs/api/openapi.yaml
git commit -m "feat: add groups and invitations API"
```

### Task 9: Добавить statistics и cursor sync

**Files:**
- Create: `backend/internal/statistics/service.go`
- Create: `backend/internal/statistics/service_test.go`
- Create: `backend/internal/statistics/repository.go`
- Create: `backend/internal/statistics/repository_test.go`
- Create: `backend/internal/sync/service.go`
- Create: `backend/internal/sync/service_test.go`
- Create: `backend/internal/httpapi/statistics_handler.go`
- Create: `backend/internal/httpapi/sync_handler.go`
- Modify: `docs/api/openapi.yaml`

**Step 1: Написать failing tests**

Проверить monthly/day/category totals, personal/group scope, timezone boundaries, exclusion of deleted purchases, stable cursor ordering и включение tombstones после cursor.

**Step 2: Реализовать агрегаты**

Считать detailed totals через `purchase_items`; не сохранять второй изменяемый итог. Queries всегда применяют тот же permission scope, что purchases API.

**Step 3: Реализовать cursor sync**

Курсор кодирует `(updated_at, id)` и подписывается сервером. Endpoint возвращает bounded page, next cursor и soft-delete tombstones. В v1 нет WebSocket.

**Step 4: Проверить**

Run: `cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./internal/statistics ./internal/sync ./internal/httpapi`

Expected: PASS.

**Step 5: Commit**

```bash
git add backend/internal/statistics backend/internal/sync backend/internal/httpapi docs/api/openapi.yaml
git commit -m "feat: add statistics and cursor sync API"
```

## Phase 4. iOS integration

### Task 10: Заменить Supabase-oriented environment на REST configuration

**Files:**
- Modify: `ios/Spendly/App/AppEnvironment.swift`
- Modify: `ios/SpendlyTests/SmokeTests.swift`
- Modify: `ios/Spendly/Resources/Development.xcconfig`
- Modify: `ios/Spendly/Resources/Staging.xcconfig`
- Modify: `ios/Spendly/Resources/Production.xcconfig`
- Create: `ios/Spendly/Core/API/APIClient.swift`
- Create: `ios/Spendly/Core/API/APIError.swift`
- Create: `ios/Spendly/Core/API/APIDTO.swift`
- Create: `ios/SpendlyTests/Core/APIClientTests.swift`

**Step 1: Написать failing URLProtocol tests**

Проверить base URL, JSON decoding, error envelope, request ID, Authorization header, 401 refresh hook, retry только идемпотентного запроса и cancellation.

**Step 2: Удалить publishable key из environment**

`AppEnvironment` хранит только API URL и публичные OAuth client IDs. Production требует HTTPS и запрещает `*.supabase.co`; secrets в bundle отсутствуют.

**Step 3: Реализовать actor-based APIClient**

Использовать `URLSession`, `Codable`, injectable transport/clock и typed endpoints. Не связывать transport DTO напрямую с domain models.

**Step 4: Проверить**

Run: `xcodegen generate && xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator -only-testing:SpendlyTests/APIClientTests -only-testing:SpendlyTests/SmokeTests`

Expected: TEST SUCCEEDED.

**Step 5: Commit**

```bash
git add project.yml ios
git commit -m "feat: add Spendly REST client"
```

### Task 11: Подключить Sign in with Apple и Google

**Files:**
- Modify: `project.yml`
- Modify: `ios/Spendly/Domain/Repositories/SessionRepository.swift`
- Create: `ios/Spendly/Core/Auth/KeychainSessionStore.swift`
- Create: `ios/Spendly/Core/Auth/RemoteSessionRepository.swift`
- Create: `ios/Spendly/Features/Authentication/AuthenticationModel.swift`
- Create: `ios/Spendly/Features/Authentication/AuthenticationView.swift`
- Create: `ios/Spendly/Features/Authentication/AppleSignInCoordinator.swift`
- Create: `ios/Spendly/Features/Authentication/GoogleSignInCoordinator.swift`
- Create: `ios/SpendlyTests/Core/RemoteSessionRepositoryTests.swift`
- Create: `ios/SpendlyTests/Features/AuthenticationModelTests.swift`

**Step 1: Написать failing session tests**

Покрыть first login, restore, refresh rotation, Keychain failure, logout cleanup, cancelled provider UI, nonce round-trip и отсутствие email/password paths.

**Step 2: Реализовать Apple flow**

Использовать AuthenticationServices, криптографический nonce и ID token exchange с `/v1/auth/apple`. Не считать Apple email постоянным identifier.

**Step 3: Добавить официальный Google Sign-In package**

Зафиксировать exact package version в `project.yml`/resolved file. Получить ID token с nonce и обменять через `/v1/auth/google`. Новая внешняя зависимость оправдана provider SDK; backend API остаётся provider-neutral.

**Step 4: Хранить tokens в Keychain**

Access/refresh tokens никогда не сохраняются в UserDefaults, SwiftData или logs. После refresh атомарно заменить пару tokens.

**Step 5: Проверить и commit**

Run: `xcodegen generate && xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator -only-testing:SpendlyTests/RemoteSessionRepositoryTests -only-testing:SpendlyTests/AuthenticationModelTests`

Expected: TEST SUCCEEDED.

```bash
git add project.yml ios Spendly.xcodeproj
git commit -m "feat: add Apple and Google authentication"
```

### Task 12: Реализовать remote repositories и offline sync

**Files:**
- Create: `ios/Spendly/Core/API/RemotePurchaseRepository.swift`
- Create: `ios/Spendly/Core/API/RemoteGroupRepository.swift`
- Create: `ios/Spendly/Core/API/RemoteStatisticsRepository.swift`
- Create: `ios/Spendly/Core/Database/CacheModels.swift`
- Create: `ios/Spendly/Core/Database/MutationRecord.swift`
- Create: `ios/Spendly/Core/Database/SyncEngine.swift`
- Create: `ios/SpendlyTests/Core/RemoteRepositoryContractTests.swift`
- Create: `ios/SpendlyTests/Core/SyncEngineTests.swift`
- Modify: `ios/Spendly/App/SpendlyApp.swift`

**Step 1: Создать contract fixtures и failing tests**

Использовать примеры из OpenAPI для quick/detailed purchase, groups, errors and sync pages. Проверить domain mapping, cache-first read, FIFO mutation queue, idempotency preservation, exponential backoff и version conflict без auto overwrite.

**Step 2: Реализовать remote adapters**

Адаптеры реализуют существующие Domain repository protocols и скрывают DTO/API details. Client-generated UUID и idempotency key переживают restart.

**Step 3: Реализовать SwiftData cache/queue**

Обновлять cache транзакционно после sync page. Tombstone удаляет/скрывает запись. Permanent permission/validation errors требуют UI resolution; network/5xx повторяются с jitter.

**Step 4: Подключить composition root**

`SpendlyApp` собирает API client, Keychain session, repositories и SyncEngine; tests используют in-memory stores and stub transport.

**Step 5: Проверить и commit**

Run: `xcodegen generate && xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator`

Expected: TEST SUCCEEDED.

```bash
git add ios project.yml Spendly.xcodeproj
git commit -m "feat: connect iOS repositories to Go API"
```

## Phase 5. Deployment and cutover

### Task 13: Добавить production Compose, Caddy и backups

**Files:**
- Create: `backend/Dockerfile`
- Create: `deploy/compose.yaml`
- Create: `deploy/Caddyfile`
- Create: `deploy/.env.example`
- Create: `deploy/backup/backup.sh`
- Create: `deploy/backup/restore.sh`
- Create: `deploy/tests/smoke.sh`
- Create: `docs/deployment.md`
- Create: `docs/backup-runbook.md`

**Step 1: Написать failing config/smoke checks**

Проверить `docker compose config`, отсутствие published port у API/PostgreSQL, read-only API root filesystem, healthchecks, volumes и успешные `/health/live`/`ready` через Caddy.

**Step 2: Собрать minimal production image**

Multi-stage build, non-root user, pinned base image digest, `CGO_ENABLED=0`, только API binary и CA certificates. Compose публикует `80/443` только у Caddy.

**Step 3: Настроить Caddy**

`Caddyfile` проксирует `api.spendly.app` в `api:8080`, задаёт request body limit/security headers и не пишет Authorization/cookies. TLS оставляет Caddy; database не доступна с host public interface.

**Step 4: Реализовать и проверить backup/restore**

Backup использует `pg_dump --format=custom`, шифрует архив, пишет checksum и применяет retention. Restore требует явный target database и отказывается работать с production database name. Выполнить restore drill в disposable test DB.

Run: `docker compose -f deploy/compose.yaml config && docker compose -f deploy/compose.yaml up -d --build && deploy/tests/smoke.sh`

Expected: PASS; `docker compose ps` показывает healthy services.

**Step 5: Commit**

```bash
git add backend/Dockerfile deploy docs/deployment.md docs/backup-runbook.md
git commit -m "ops: deploy API with Caddy and PostgreSQL"
```

### Task 14: Добавить CI и удалить Supabase после доказанного cutover

**Files:**
- Create: `.github/workflows/backend.yml`
- Create: `.github/workflows/ios.yml`
- Modify: `.gitignore`
- Modify: `README.md`
- Modify: `docs/data-model.md`
- Delete: `supabase/config.toml`
- Delete: `supabase/migrations/0001_initial_schema.sql`
- Delete: `supabase/seed.sql`
- Delete: `supabase/tests/schema.test.sql`

**Step 1: Создать CI jobs**

Backend job запускает `gofmt` check, `go vet`, `go test -race`, migration integration tests и Docker build. iOS job генерирует Xcode project и запускает все XCTest. Зафиксировать версии Go, PostgreSQL, XcodeGen и images.

**Step 2: Выполнить полный compatibility gate**

Run:

```bash
cd backend && TEST_DATABASE_URL=postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable go test -race ./...
xcodegen generate
xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator
docker compose -f deploy/compose.yaml config
deploy/tests/smoke.sh
```

Expected: все команды PASS; OpenAPI fixtures совпадают с iOS contract tests.

**Step 3: Убедиться, что Supabase больше не используется**

Run: `rg -n -i 'supabase|postgrest|service_role' --glob '!docs/plans/2026-08-24-spendly-swiftui-production-*' .`

Expected: только миграционные/исторические упоминания, ни одного runtime import, URL, key или build setting.

**Step 4: Удалить Supabase runtime artifacts и обновить docs**

Удалить каталог только после Step 2–3. Обновить README/data model так, чтобы единственным runtime backend был Go API. Старые утверждённые планы оставить как историю; новый design явно их supersede.

**Step 5: Финальная проверка и commit**

Повторить полный compatibility gate из Step 2.

```bash
git add .github .gitignore README.md docs backend ios deploy project.yml Spendly.xcodeproj
git add -u supabase
git commit -m "chore: complete Go backend cutover"
```

## Completion criteria

- Первый валидный Google/Apple login атомарно создаёт пользователя; повторный возвращает тот же user ID.
- Независимые Apple и Google identities не объединяются автоматически.
- iOS не содержит Supabase SDK, keys или URLs и работает только через versioned Go REST API.
- Purchases/groups/statistics/sync применяют permissions server-side и проходят негативные integration tests.
- API, PostgreSQL и Caddy работают на одном Compose host; наружу опубликованы только `80/443`.
- Refresh rotation/reuse detection, idempotency, optimistic concurrency, backups и restore drill проверены тестами.
- Backend/iOS CI и end-to-end smoke test проходят на чистом checkout.
