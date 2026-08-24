# Spendly SwiftUI Production Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Создать production-ready iOS-приложение Spendly на SwiftUI с offline-first кэшем, Supabase backend и доступным из РФ reverse proxy.

**Architecture:** SwiftUI-клиент разделён на Domain, Core и feature-модули; Supabase скрыт за repository-протоколами и собственным API-доменом. PostgreSQL/RLS являются источником истины для данных и прав, SwiftData — локальным кэшем и очередью мутаций, proxy — только транспортным слоем.

**Tech Stack:** Swift 6, SwiftUI, Observation, SwiftData, XCTest/XCUITest, Supabase Swift, PostgreSQL, Supabase CLI, SQL/pgTAP, Deno Edge Functions, Nginx, Docker Compose, GitHub Actions.

---

Все пути ниже указаны относительно корня нового репозитория `spendly-native`. Перед началом агент обязан прочитать `docs/spendly-swiftui-production-design.md` и сверить доступные версии Xcode, Swift и Supabase CLI. Версии фиксируются в первом коммите и не обновляются попутно.

## Phase 1. Foundation

### Task 1: Создать воспроизводимую структуру проекта

**Files:**
- Create: `project.yml`
- Create: `ios/Spendly/App/SpendlyApp.swift`
- Create: `ios/Spendly/App/AppEnvironment.swift`
- Create: `ios/Spendly/Resources/Development.xcconfig`
- Create: `ios/Spendly/Resources/Staging.xcconfig`
- Create: `ios/Spendly/Resources/Production.xcconfig`
- Create: `ios/SpendlyTests/SmokeTests.swift`
- Create: `.gitignore`
- Create: `README.md`

**Step 1: Зафиксировать toolchain**

Run:

```bash
xcodebuild -version
swift --version
supabase --version
docker --version
```

Expected: команды завершаются успешно; версии записаны в `README.md`. Если инструмента нет, остановиться и описать установку, не подменять его случайной альтернативой.

**Step 2: Написать failing smoke test**

```swift
import XCTest
@testable import Spendly

final class SmokeTests: XCTestCase {
    func testApplicationEnvironmentUsesProxyURL() throws {
        let environment = try AppEnvironment(
            apiBaseURL: XCTUnwrap(URL(string: "https://api.spendly.app")),
            publishableKey: "test-key"
        )
        XCTAssertEqual(environment.apiBaseURL.host, "api.spendly.app")
    }
}
```

**Step 3: Создать минимальный проект**

`AppEnvironment` должен принимать конфигурацию через initializer, валидировать HTTPS вне DEBUG и никогда не содержать hardcoded production secret. `SpendlyApp` пока показывает `Text("Spendly")`.

**Step 4: Сгенерировать и проверить проект**

Run:

```bash
xcodegen generate
xcodebuild -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator build
xcodebuild -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator test
```

Expected: BUILD SUCCEEDED, TEST SUCCEEDED.

**Step 5: Commit**

```bash
git add project.yml ios .gitignore README.md
git commit -m "chore: scaffold Spendly native workspace"
```

### Task 2: Реализовать чистую доменную модель

**Files:**
- Create: `ios/Spendly/Domain/Models/Money.swift`
- Create: `ios/Spendly/Domain/Models/Purchase.swift`
- Create: `ios/Spendly/Domain/Models/ExpenseContext.swift`
- Create: `ios/Spendly/Domain/Models/Group.swift`
- Create: `ios/Spendly/Domain/Models/AppFailure.swift`
- Create: `ios/Spendly/Domain/Repositories/PurchaseRepository.swift`
- Create: `ios/Spendly/Domain/Repositories/GroupRepository.swift`
- Create: `ios/Spendly/Domain/Repositories/SessionRepository.swift`
- Create: `ios/SpendlyTests/Domain/MoneyTests.swift`
- Create: `ios/SpendlyTests/Domain/PurchaseTests.swift`

**Step 1: Написать failing tests для денег и заказа**

Проверить:

- деньги не используют `Double`;
- разные валюты нельзя складывать;
- quick purchase возвращает собственную сумму;
- detailed purchase возвращает сумму позиций;
- пустой detailed purchase не проходит валидацию;
- отрицательная и переполняющая сумма отклоняется.

```swift
func testDetailedPurchaseTotalIsDerivedFromItems() throws {
    let purchase = try Purchase.fixture(items: [
        .fixture(amount: Money(minorUnits: 35_500, currencyCode: "RUB")),
        .fixture(amount: Money(minorUnits: 12_900, currencyCode: "RUB"))
    ])
    XCTAssertEqual(purchase.total.minorUnits, 48_400)
}
```

**Step 2: Запустить тесты и подтвердить FAIL**

Run: `xcodebuild test -project Spendly.xcodeproj -scheme Spendly -only-testing:SpendlyTests/MoneyTests -only-testing:SpendlyTests/PurchaseTests`

Expected: FAIL — модели отсутствуют.

**Step 3: Реализовать минимальные value types**

Все идентификаторы — отдельные `RawRepresentable`, `Codable`, `Sendable`, `Hashable` типы поверх UUID. `Purchase` — enum либо структура с валидируемым `kind`; UI не должен проверять несогласованные nullable-поля.

**Step 4: Добавить repository-контракты**

```swift
protocol PurchaseRepository: Sendable {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase]
    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase
    func delete(id: PurchaseID, expectedVersion: Int64) async throws
}
```

**Step 5: Проверить и commit**

Run: `xcodebuild test -project Spendly.xcodeproj -scheme Spendly -only-testing:SpendlyTests/Domain`

Expected: TEST SUCCEEDED.

```bash
git add ios/Spendly/Domain ios/SpendlyTests/Domain
git commit -m "feat: add Spendly domain model"
```

## Phase 2. Supabase backend

### Task 3: Создать локальный Supabase и базовую схему

**Files:**
- Create: `supabase/config.toml`
- Create: `supabase/migrations/0001_initial_schema.sql`
- Create: `supabase/seed.sql`
- Create: `supabase/tests/schema.test.sql`
- Create: `docs/data-model.md`

**Step 1: Инициализировать локальную конфигурацию**

Run: `supabase init`

Expected: создана конфигурация без production credentials.

**Step 2: Написать failing SQL tests**

Проверить существование `profiles`, `groups`, `group_members`, `group_invitations`, `purchases`, `purchase_items`; constraints для kind, положительной суммы, валюты, уникальной позиции и owner membership.

**Step 3: Создать миграцию**

Следовать схеме из design document. Обязательно:

- `uuid` client-generated primary keys;
- `bigint` для minor units;
- `timestamptz` для событий;
- `date local_date` и `text time_zone`;
- `version bigint not null default 1`;
- `deleted_at` для soft delete;
- indexes по `(owner_id, local_date)`, `(group_id, local_date)`, `updated_at`;
- trigger для `updated_at` и увеличения `version`.

**Step 4: Поднять чистую базу**

Run:

```bash
supabase start
supabase db reset
supabase test db
```

Expected: schema tests PASS.

**Step 5: Commit**

```bash
git add supabase docs/data-model.md
git commit -m "feat: add Supabase expense schema"
```

### Task 4: Реализовать и доказать RLS

**Files:**
- Create: `supabase/migrations/0002_row_level_security.sql`
- Create: `supabase/tests/rls_profiles.test.sql`
- Create: `supabase/tests/rls_groups.test.sql`
- Create: `supabase/tests/rls_purchases.test.sql`
- Create: `docs/permissions-matrix.md`

**Step 1: Составить permissions matrix**

Для каждой таблицы перечислить select/insert/update/delete для anonymous, owner, ordinary member, expense manager, unrelated authenticated user и service role.

**Step 2: Написать негативные тесты первыми**

Минимальные сценарии:

- пользователь B не видит личные покупки A;
- неучастник не видит группу;
- member не меняет чужую покупку;
- подмена `owner_id` отклоняется;
- `user_metadata` не влияет на доступ;
- архивная группа запрещает новые покупки.

**Step 3: Запустить и подтвердить FAIL**

Run: `supabase test db`

Expected: RLS tests FAIL до добавления policies.

**Step 4: Добавить helper-функции и policies**

Security-definer helpers размещать в private schema, фиксировать `search_path = ''`, отзывать лишние execute grants. Не создавать policy вида `using (true)` для authenticated.

**Step 5: Проверить тесты и advisors**

Run:

```bash
supabase db reset
supabase test db
supabase db lint --level warning
```

Expected: PASS; нет security warnings про открытые таблицы или небезопасный RLS.

**Step 6: Commit**

```bash
git add supabase/migrations/0002_row_level_security.sql supabase/tests docs/permissions-matrix.md
git commit -m "feat: enforce expense access with RLS"
```

### Task 5: Добавить транзакционные RPC и приглашения

**Files:**
- Create: `supabase/migrations/0003_purchase_commands.sql`
- Create: `supabase/tests/purchase_commands.test.sql`
- Create: `supabase/functions/create-invitation/index.ts`
- Create: `supabase/functions/accept-invitation/index.ts`
- Create: `supabase/functions/_shared/errors.ts`
- Create: `supabase/functions/tests/invitations.test.ts`
- Create: `docs/api-contract.md`

**Step 1: Написать failing tests**

Проверить атомарное создание detailed purchase, derived total, idempotency, expected version, rollback при неверной позиции, expiry/revocation invitation и невозможность повторного принятия.

**Step 2: Реализовать SQL commands**

Создать функции `create_purchase`, `update_purchase`, `soft_delete_purchase` с явными параметрами и проверкой `auth.uid()`. RPC должна возвращать нормализованную покупку с позициями и новой версией.

**Step 3: Реализовать Edge Functions**

Открытый invitation token генерируется криптографически, в БД сохраняется только hash. Service role используется только внутри функции и только после ручной проверки caller JWT и permissions.

**Step 4: Описать контракт**

Для каждого endpoint/RPC зафиксировать request, response, error code, idempotency semantics и example fixture. Не экспортировать физическую схему напрямую как доменную модель iOS.

**Step 5: Проверить**

Run:

```bash
supabase test db
deno test supabase/functions/tests --allow-env
```

Expected: PASS.

**Step 6: Commit**

```bash
git add supabase docs/api-contract.md
git commit -m "feat: add transactional purchase API"
```

## Phase 3. Reachability proxy

### Task 6: Реализовать reverse proxy без бизнес-логики

**Files:**
- Create: `proxy/nginx.conf.template`
- Create: `proxy/Dockerfile`
- Create: `proxy/compose.yaml`
- Create: `proxy/.env.example`
- Create: `proxy/tests/smoke.sh`
- Create: `proxy/tests/websocket.sh`
- Create: `docs/proxy-runbook.md`

**Step 1: Написать failing smoke tests**

Tests должны проверять `/healthz`, `/auth/v1/health`, `/rest/v1/`, Storage upload/download, Functions и WebSocket handshake `/realtime/v1/websocket`. Отдельно проверить, что upstream URL и ключи отсутствуют в response headers и логах.

**Step 2: Создать минимальную конфигурацию**

Обязательные свойства:

```nginx
location /realtime/v1/ {
    proxy_pass https://supabase_upstream;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "upgrade";
    proxy_read_timeout 3600s;
}

location /storage/v1/ {
    proxy_pass https://supabase_upstream;
    proxy_buffering off;
    proxy_request_buffering off;
}
```

Также корректно передавать upstream Host/SNI, `Authorization`, `apikey`, query string и request ID. Запретить proxy caching авторизованных ответов. Не добавлять service role и не расшифровывать JWT.

**Step 3: Добавить operational controls**

TLS, rate limit, body limits, timeouts, structured redacted logs, non-root container, read-only filesystem, healthcheck и graceful reload. Описать DNS failover и ротацию upstream.

**Step 4: Проверить локально**

Run:

```bash
docker compose -f proxy/compose.yaml config
docker build -t spendly-proxy:test proxy
bash proxy/tests/smoke.sh
bash proxy/tests/websocket.sh
```

Expected: все prefixes доступны; WebSocket получает 101; secrets отсутствуют в логах.

**Step 5: Commit**

```bash
git add proxy docs/proxy-runbook.md
git commit -m "feat: add Supabase reachability proxy"
```

## Phase 4. iOS data and authentication

### Task 7: Реализовать transport и безопасную сессию

**Files:**
- Create: `ios/Spendly/Core/API/SupabaseClientFactory.swift`
- Create: `ios/Spendly/Core/API/PurchaseDTO.swift`
- Create: `ios/Spendly/Core/API/APIErrorMapper.swift`
- Create: `ios/Spendly/Core/Auth/KeychainSessionStorage.swift`
- Create: `ios/Spendly/Core/Auth/SupabaseSessionRepository.swift`
- Create: `ios/SpendlyTests/Core/SupabaseClientFactoryTests.swift`
- Create: `ios/SpendlyTests/Core/APIErrorMapperTests.swift`
- Create: `ios/SpendlyTests/Core/KeychainSessionStorageTests.swift`

**Step 1: Написать tests**

Проверить, что factory принимает только proxy base URL, DTO строго декодирует `int64` суммы и ISO dates, error mapper различает 401/403/409/422/429/offline, а Keychain storage удаляет сессию при logout.

**Step 2: Реализовать client factory**

```swift
static func make(environment: AppEnvironment) -> SupabaseClient {
    SupabaseClient(
        supabaseURL: environment.apiBaseURL,
        supabaseKey: environment.publishableKey,
        options: .init(auth: .init(flowType: .pkce))
    )
}
```

Добавить DEBUG assertion, запрещающий host с suffix `.supabase.co`. Publishable key не считать секретом; service role в типе конфигурации не существует.

**Step 3: Реализовать auth lifecycle**

Поддержать Sign in with Apple, email OTP, refresh, logout, Universal Link и восстановление сессии. Email verification URL должен идти через собственный домен либо app Universal Link.

**Step 4: Проверить и commit**

Run: `xcodebuild test -project Spendly.xcodeproj -scheme Spendly -only-testing:SpendlyTests/Core`

Expected: TEST SUCCEEDED.

```bash
git add ios/Spendly/Core ios/SpendlyTests/Core
git commit -m "feat: add secure Supabase transport and auth"
```

### Task 8: Реализовать SwiftData cache и sync queue

**Files:**
- Create: `ios/Spendly/Core/Database/CachedPurchase.swift`
- Create: `ios/Spendly/Core/Database/PendingMutation.swift`
- Create: `ios/Spendly/Core/Database/ModelContainerFactory.swift`
- Create: `ios/Spendly/Core/Sync/SyncEngine.swift`
- Create: `ios/Spendly/Core/Sync/RetryPolicy.swift`
- Create: `ios/Spendly/Core/API/SupabasePurchaseRepository.swift`
- Create: `ios/SpendlyTests/Core/SyncEngineTests.swift`
- Create: `ios/SpendlyTests/Core/PurchaseRepositoryTests.swift`

**Step 1: Написать failing tests**

Сценарии: cache-first read, remote refresh, offline create, restart with pending mutation, idempotent retry, exponential backoff with jitter, 409 conflict, 403 permanent failure и logout isolation.

**Step 2: Создать in-memory SwiftData test container**

Каждый тест получает чистый container. Production store именуется по user ID; данные двух аккаунтов не смешиваются.

**Step 3: Реализовать sync state machine**

```text
queued → sending → succeeded
                 ↘ retryWaiting → queued
                 ↘ conflict
                 ↘ permanentlyFailed
```

Network status используется только как подсказка: реальная попытка запроса остаётся источником истины. Realtime лишь инвалидирует cache и запускает fetch.

**Step 4: Проверить crash-safe поведение**

После принудительной остановки между server success и local acknowledgement повторная отправка с тем же idempotency key не создаёт дубль.

**Step 5: Проверить и commit**

Run: `xcodebuild test -project Spendly.xcodeproj -scheme Spendly -only-testing:SpendlyTests/SyncEngineTests -only-testing:SpendlyTests/PurchaseRepositoryTests`

Expected: TEST SUCCEEDED.

```bash
git add ios/Spendly/Core/Database ios/Spendly/Core/Sync ios/Spendly/Core/API ios/SpendlyTests/Core
git commit -m "feat: add offline expense synchronization"
```

## Phase 5. Native product UI

### Task 9: Создать navigation shell и design system

**Files:**
- Create: `ios/Spendly/App/AppState.swift`
- Create: `ios/Spendly/App/AppRouter.swift`
- Create: `ios/Spendly/App/RootView.swift`
- Create: `ios/Spendly/Core/DesignSystem/SpendlyTokens.swift`
- Create: `ios/Spendly/Core/DesignSystem/MoneyText.swift`
- Create: `ios/Spendly/Core/DesignSystem/LoadableView.swift`
- Create: `ios/SpendlyUITests/NavigationTests.swift`

**Step 1: Написать failing UI test**

Проверить четыре вкладки, сохранение выбранного context/date при смене вкладки и отсутствие горизонтального overflow на поддерживаемых симуляторах.

**Step 2: Реализовать `TabView` и отдельные `NavigationStack`**

Использовать системные semantic colors, SF Symbols, Dynamic Type и touch target 44 pt. Не переносить CSS-пиксели буквально.

**Step 3: Добавить accessibility tests**

Каждая icon-only action имеет label; денежные значения читаются одной фразой; focus order соответствует визуальному.

**Step 4: Проверить и commit**

Run: `xcodebuild test -project Spendly.xcodeproj -scheme Spendly -only-testing:SpendlyUITests/NavigationTests`

```bash
git add ios/Spendly/App ios/Spendly/Core/DesignSystem ios/SpendlyUITests
git commit -m "feat: add native navigation shell"
```

### Task 10: Реализовать authentication flow

**Files:**
- Create: `ios/Spendly/Features/Authentication/AuthenticationModel.swift`
- Create: `ios/Spendly/Features/Authentication/SignInView.swift`
- Create: `ios/Spendly/Features/Authentication/EmailCodeView.swift`
- Create: `ios/SpendlyTests/Features/AuthenticationModelTests.swift`
- Create: `ios/SpendlyUITests/AuthenticationFlowTests.swift`

**Steps:**

1. Написать failing tests для restore session, Apple cancellation, invalid OTP, expired session и offline state.
2. Реализовать model как явную state machine, не набор независимых booleans.
3. Реализовать Sign in with Apple и email OTP через `SessionRepository`.
4. Проверить Universal Link на simulator/device fixture.
5. Запустить unit/UI tests.
6. Commit: `feat: add production authentication flow`.

### Task 11: Реализовать дневные расходы

**Files:**
- Create: `ios/Spendly/Features/Expenses/ExpensesModel.swift`
- Create: `ios/Spendly/Features/Expenses/ExpensesView.swift`
- Create: `ios/Spendly/Features/Expenses/WeekStrip.swift`
- Create: `ios/Spendly/Features/Expenses/PurchaseRow.swift`
- Create: `ios/Spendly/Features/Expenses/PurchaseDetailsView.swift`
- Create: `ios/Spendly/Features/Expenses/ContextPicker.swift`
- Create: `ios/SpendlyTests/Features/ExpensesModelTests.swift`
- Create: `ios/SpendlyUITests/ExpensesFlowTests.swift`

**Steps:**

1. Написать tests для personal/group selectors, day ordering, totals, date preservation и cache/error states.
2. Реализовать model только через use cases/repositories.
3. Реализовать экран по утверждённому UX: compact month row, week navigation, purchase list, plus action.
4. Реализовать детали заказа и context sheet.
5. Проверить empty/loading/cached-offline/error/pending/conflict states.
6. Проверить Dynamic Type XXXL, VoiceOver и dark mode.
7. Run focused unit и XCUITest suites.
8. Commit: `feat: add daily expense experience`.

### Task 12: Реализовать progressive expense form

**Files:**
- Create: `ios/Spendly/Features/AddExpense/ExpenseDraft.swift`
- Create: `ios/Spendly/Features/AddExpense/AddExpenseModel.swift`
- Create: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Create: `ios/Spendly/Features/AddExpense/ProductLineEditor.swift`
- Create: `ios/Spendly/Features/AddExpense/CategorySuggestions.swift`
- Create: `ios/SpendlyTests/Features/AddExpenseModelTests.swift`
- Create: `ios/SpendlyUITests/AddExpenseFlowTests.swift`

**Steps:**

1. Написать tests для quick/detailed transition, live total, delivery line, validation, draft restore и double submit.
2. Реализовать pure draft reducer/model.
3. Реализовать системные money, date, time и context controls.
4. Сохранять draft при background/termination.
5. Добавить pending confirmation и ненавязчивый sync status.
6. Запустить tests, включая offline create и retry after restart.
7. Commit: `feat: add resilient expense entry`.

### Task 13: Реализовать календарь и статистику

**Files:**
- Create: `ios/Spendly/Features/Calendar/CalendarModel.swift`
- Create: `ios/Spendly/Features/Calendar/MonthCalendarView.swift`
- Create: `ios/Spendly/Features/Calendar/YearPickerView.swift`
- Create: `ios/Spendly/Features/Statistics/StatisticsModel.swift`
- Create: `ios/Spendly/Features/Statistics/StatisticsView.swift`
- Create: `ios/Spendly/Domain/UseCases/CalculateStatistics.swift`
- Create: `ios/SpendlyTests/Domain/CalculateStatisticsTests.swift`
- Create: `ios/SpendlyUITests/CalendarStatisticsTests.swift`

**Steps:**

1. Портировать утверждённые deterministic fixtures из веб-прототипа.
2. Написать tests для daily/category/context/member aggregation, leap year, locale и time zone boundary.
3. Реализовать pure statistics use case.
4. Реализовать month grid, year selection и переход day → expenses.
5. Реализовать нативные Swift Charts только если они улучшают читаемость; данные и accessibility summary обязательны независимо от графика.
6. Запустить unit/UI tests.
7. Commit: `feat: add calendar and expense statistics`.

### Task 14: Реализовать группы и профиль

**Files:**
- Create: `ios/Spendly/Features/Groups/GroupsModel.swift`
- Create: `ios/Spendly/Features/Groups/GroupsView.swift`
- Create: `ios/Spendly/Features/Groups/GroupDetailsView.swift`
- Create: `ios/Spendly/Features/Groups/InvitationView.swift`
- Create: `ios/Spendly/Features/Profile/ProfileView.swift`
- Create: `ios/SpendlyTests/Features/GroupsModelTests.swift`
- Create: `ios/SpendlyUITests/GroupFlowTests.swift`

**Steps:**

1. Написать tests по permissions matrix.
2. Реализовать create/archive group, invitation create/accept/revoke и role management.
3. Скрывать недоступные действия в UI, но считать RLS единственной границей безопасности.
4. Реализовать profile, logout и account deletion request.
5. Проверить expired link, removed member, archived group и lost session.
6. Запустить tests.
7. Commit: `feat: add groups and profile management`.

## Phase 6. Production hardening

### Task 15: Добавить privacy, observability и accessibility gates

**Files:**
- Create: `ios/Spendly/PrivacyInfo.xcprivacy`
- Create: `ios/Spendly/Core/Logging/AppLogger.swift`
- Create: `docs/privacy-data-map.md`
- Create: `docs/incident-response.md`
- Create: `scripts/check-for-secrets.sh`
- Create: `scripts/check-direct-supabase-hosts.sh`

**Steps:**

1. Написать failing scripts, находящие service role, JWT, `.supabase.co` в production bundle и логирование DTO.
2. Реализовать privacy-safe logger с allowlist полей.
3. Заполнить privacy manifest и data map.
4. Запустить Accessibility Inspector и устранить blockers.
5. Проверить scripts на намеренно небезопасной fixture, затем на репозитории.
6. Commit: `chore: add privacy and security release gates`.

### Task 16: Настроить CI/CD и release verification

**Files:**
- Create: `.github/workflows/ios.yml`
- Create: `.github/workflows/backend.yml`
- Create: `.github/workflows/proxy.yml`
- Create: `.github/workflows/deploy-staging.yml`
- Create: `docs/release-checklist.md`
- Create: `docs/disaster-recovery.md`

**Step 1: Настроить required checks**

- iOS build, unit tests и выбранный XCUITest suite;
- SwiftFormat/SwiftLint только если команда утвердит dependency; иначе compiler warnings и собственные checks;
- clean Supabase migration + SQL tests + lint;
- Edge Function tests;
- proxy build, config validation, HTTP/WebSocket smoke tests;
- secret scan и запрет прямых Supabase hosts.

**Step 2: Настроить staging deployment**

Миграции сначала применяются к staging. Production требует manual approval, backup confirmation и documented rollback. Proxy image публикуется immutable digest.

**Step 3: Провести полный release rehearsal**

Run:

```bash
xcodebuild clean test -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 16'
supabase db reset
supabase test db
deno test supabase/functions/tests --allow-env
docker build -t spendly-proxy:release proxy
bash proxy/tests/smoke.sh
bash proxy/tests/websocket.sh
bash scripts/check-for-secrets.sh
bash scripts/check-direct-supabase-hosts.sh
```

Expected: все проверки PASS на чистом checkout.

**Step 4: Провести сетевую проверку из целевого региона**

На реальном устройстве без VPN проверить sign-in, token refresh, REST, Realtime reconnect, invitation Universal Link и upload. Зафиксировать дату, сеть, build и результат в release evidence.

**Step 5: Commit**

```bash
git add .github docs scripts
git commit -m "ci: add production release pipeline"
```

## Final acceptance

Перед заявлением о готовности агент обязан предоставить:

1. commit hash каждого этапа;
2. полный вывод clean CI-equivalent проверок;
3. список миграций и RLS test count;
4. подтверждение отсутствия `.supabase.co` в production binary/config;
5. результаты реального сетевого теста без VPN;
6. известные ограничения и rollback procedure;
7. screenshots основных экранов на компактном iPhone, dark mode и Dynamic Type XXXL;
8. подтверждение, что service role отсутствует в iOS и proxy.

Нельзя считать работу завершённой только по успешной сборке или наличию экранов. Production-ready означает доказанные права доступа, восстановление после сбоев, воспроизводимое развёртывание и проверенную доступность через proxy.
