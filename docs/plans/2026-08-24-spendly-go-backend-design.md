# Spendly Go Backend Design

**Дата:** 2026-08-24  
**Статус:** утверждено  
**Заменяет:** backend, authentication, proxy и deployment-разделы прежнего Supabase-дизайна

## 1. Цель и границы

Spendly переходит с managed Supabase на собственный Go API и PostgreSQL. iOS-приложение, доменная модель расходов, SwiftData-кэш и offline-first подход сохраняются. Backend и инфраструктура находятся в том же репозитории, в его корне, без создания отдельного проекта или вложенного репозитория.

Первая версия рассчитана на двух пользователей и один VDS, но не должна содержать решения, мешающие обычному вертикальному масштабированию. В scope входят авторизация через Google и Apple, расходы, группы, статистика, синхронизация, миграции, резервное копирование и базовая эксплуатация. Supabase, email/password, email OTP и автоматическое объединение аккаунтов разных провайдеров не используются.

## 2. Выбранный подход

Используется модульный монолит на Go:

```text
iOS client -> HTTPS -> Caddy -> Go API -> PostgreSQL
```

- Go API владеет бизнес-правилами, правами доступа, OAuth-проверкой и транзакциями.
- PostgreSQL является серверным источником истины.
- Caddy завершает TLS, автоматически обновляет сертификаты и проксирует запросы в Go API.
- Все сервисы запускаются на одном VDS через Docker Compose.
- PostgreSQL не публикуется в интернет и доступен только из внутренней Docker-сети.

Этот вариант выбран вместо Supabase и набора микросервисов. Он даёт полный контроль над backend без лишней операционной сложности для двух пользователей.

## 3. Структура репозитория

```text
spendly-ios/
├── ios/
├── backend/
│   ├── cmd/api/main.go
│   ├── internal/
│   │   ├── auth/
│   │   ├── purchases/
│   │   ├── groups/
│   │   ├── statistics/
│   │   ├── sync/
│   │   ├── httpapi/
│   │   ├── postgres/
│   │   ├── config/
│   │   └── observability/
│   ├── migrations/
│   ├── tests/
│   ├── go.mod
│   └── go.sum
├── deploy/
│   ├── compose.yaml
│   ├── Caddyfile
│   ├── .env.example
│   └── backup/
├── docs/
├── scripts/
└── .github/workflows/
```

Пакеты внутри `internal` разделяются по бизнес-возможностям, но работают в одном процессе и могут разделять общий пул подключений к PostgreSQL. Новые сервисы выделяются только при доказанной необходимости.

## 4. Аутентификация и идентификация

### 4.1 Вход

iOS поддерживает только Sign in with Google и Sign in with Apple:

1. iOS получает ID token провайдера с nonce.
2. Клиент отправляет token и provider в Go API.
3. API проверяет подпись, issuer, audience, expiry и nonce по публичным ключам провайдера.
4. Пользователь определяется только по паре `(provider, provider_subject)`, где `provider_subject` — проверенный claim `sub`.
5. Если идентичность отсутствует, API в одной транзакции создаёт `users`, `user_identities` и профиль.
6. API выдаёт собственный короткоживущий access token и ротируемый opaque refresh token.
7. iOS хранит сессию только в Keychain.

Email и отображаемое имя являются необязательными атрибутами профиля и не используются как ключ идентичности. Apple relay email, device ID и совпадение имён не применяются для объединения пользователей.

### 4.2 Разные провайдеры

Google и Apple не имеют общего надёжного идентификатора. Поэтому первый независимый вход через каждый провайдер создаёт отдельный Spendly-аккаунт. Автоматическое объединение по email и UI для привязки или слияния аккаунтов не входят в первую версию.

Ограничения базы:

```text
UNIQUE(provider, provider_subject)
UNIQUE(user_id, provider)
```

Если связывание будет добавлено позднее, уже занятая идентичность должна приводить к явному конфликту, а не к автоматическому переносу между пользователями.

### 4.3 Сессии

- Access token живёт недолго и содержит внутренний `user_id`, session ID и минимальный набор claims.
- Refresh token хранится в базе только как криптографический hash.
- Refresh выполняет обязательную ротацию; повторное предъявление использованного токена отзывает семейство сессий.
- Logout отзывает текущую сессию; logout-all отзывает все сессии пользователя.
- Смена ключей подписи поддерживает период перекрытия активного и предыдущего ключа.

## 5. Данные и права

Существующая модель `groups`, `group_members`, `group_invitations`, `purchases` и `purchase_items` переносится из Supabase SQL в обычные PostgreSQL-миграции. Добавляются:

- `users` — внутренняя учётная запись;
- `user_identities` — внешние Google/Apple identities;
- `user_sessions` — refresh-сессии и их отзыв;
- `profiles` с внешним ключом на `users`, а не `auth.users`.

Деньги остаются целыми minor units, timestamps — UTC, локальная дата и часовой пояс операции сохраняются отдельно. Detailed purchase и позиции изменяются атомарно. Client-generated UUID и idempotency key защищают создание расхода от повторной отправки. Обновления используют optimistic concurrency через `version`.

RLS не является границей безопасности. Каждый HTTP command/query получает аутентифицированного пользователя из middleware, а application service проверяет владение, членство и роль до обращения к repository. PostgreSQL constraints дополнительно защищают инварианты данных.

## 6. HTTP API и синхронизация

API имеет версионированный префикс `/v1`. Основные группы endpoints:

- `/v1/auth/google`, `/v1/auth/apple`, `/v1/auth/refresh`, `/v1/auth/logout`;
- `/v1/me`;
- `/v1/purchases`;
- `/v1/groups` и `/v1/group-invitations`;
- `/v1/statistics`;
- `/v1/sync`;
- `/health/live` и `/health/ready`.

Ответы используют единый JSON error envelope с стабильным машинным `code`, пользовательским `message` и request ID. Валидационные ошибки, отсутствие прав, version conflict и повтор idempotency key различаются отдельными кодами.

Offline-first клиент сначала показывает SwiftData-кэш. Синхронизация отправляет локальную очередь идемпотентных мутаций, затем получает изменения по курсору. Для двух пользователей polling и синхронизации при foreground достаточно; WebSocket и realtime-инфраструктура в первую версию не входят.

## 7. Ошибки и надёжность

- Все составные изменения выполняются в PostgreSQL-транзакциях.
- HTTP timeouts, ограничения размера body и graceful shutdown задаются явно.
- Внешние JWKS кэшируются с ограниченным временем жизни; неизвестный `kid` вызывает контролируемое обновление ключей.
- Невалидный provider token никогда не создаёт пользователя.
- Логи структурированы и содержат request ID, но не access/refresh/ID tokens, invitation tokens или финансовые payload.
- Rate limits применяются прежде всего к auth, refresh и invitation endpoints.
- Readiness зависит от доступности базы; liveness проверяет только процесс.

## 8. Развёртывание

Docker Compose запускает три контейнера:

- `caddy` публикует только `80/443`;
- `api` доступен только во внутренней сети;
- `postgres` доступен только во внутренней сети и использует persistent volume.

Секреты находятся в VDS environment-файле, который не коммитится. Миграции выполняются отдельной одноразовой командой перед запуском новой версии API. Deploy должен сохранять предыдущий image tag для отката.

Для базы настраиваются ежедневные `pg_dump`, шифрование архива, ограничение retention и периодическая проверка восстановления. Резервная копия не считается рабочей, пока не проверено восстановление в отдельную базу.

## 9. Проверка

- Unit tests покрывают domain/application services, permissions, token validation и error mapping.
- Repository integration tests запускаются против настоящего PostgreSQL.
- HTTP tests проверяют auth, CRUD, idempotency, concurrency conflicts и запреты доступа.
- Миграции проверяются как с чистой базы, так и поверх текущей версии.
- iOS contract tests используют зафиксированные JSON fixtures API.
- Compose smoke test проверяет HTTPS routing, liveness/readiness и отсутствие публичного PostgreSQL-порта.
- Отдельный restore drill доказывает восстановление резервной копии.

## 10. Миграция с текущего состояния

Текущая Supabase-миграция не развёрнута как production dependency и используется как источник для переноса схемы. Работа выполняется поэтапно:

1. Создать Go workspace, конфигурацию и health endpoints.
2. Перенести схему в backend migrations и добавить auth/session tables.
3. Реализовать Google/Apple token exchange и собственные сессии.
4. Реализовать purchases, groups, statistics и cursor sync.
5. Переключить iOS repository implementations на REST API.
6. Добавить Compose, Caddy, backup и CI.
7. После прохождения contract и end-to-end tests удалить Supabase SDK/configuration и каталог `supabase`.

Удаление Supabase выполняется только после того, как Go API полностью покрывает используемые клиентом сценарии.
