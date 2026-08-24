package purchases

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestRepositoryCreateIsIdempotentAndPrivate(t *testing.T) {
	pool := purchaseTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	other := auth.UserID("33333333-3333-4333-8333-333333333333")
	insertPurchaseUser(t, pool, owner)
	insertPurchaseUser(t, pool, other)
	repository := NewPostgresRepository(pool)
	draft := validQuickDraft()

	first, err := repository.Create(context.Background(), owner, draft, "44444444-4444-4444-8444-444444444444")
	if err != nil {
		t.Fatalf("create: %v", err)
	}
	second, err := repository.Create(context.Background(), owner, draft, "44444444-4444-4444-8444-444444444444")
	if err != nil {
		t.Fatalf("repeat create: %v", err)
	}
	if first.ID != second.ID {
		t.Fatal("idempotent response changed")
	}
	visible, err := repository.List(context.Background(), owner, Scope{}, draft.SpentAt.Add(-time.Second), draft.SpentAt.Add(time.Second))
	if err != nil || len(visible) != 1 {
		t.Fatalf("owner list: %d %v", len(visible), err)
	}
	hidden, err := repository.List(context.Background(), other, Scope{}, draft.SpentAt.Add(-time.Second), draft.SpentAt.Add(time.Second))
	if err != nil || len(hidden) != 0 {
		t.Fatalf("other user saw purchase: %d %v", len(hidden), err)
	}
}

func TestRepositoryRejectsChangedIdempotentRequest(t *testing.T) {
	pool := purchaseTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	insertPurchaseUser(t, pool, owner)
	repository := NewPostgresRepository(pool)
	draft := validQuickDraft()
	key := "44444444-4444-4444-8444-444444444444"
	if _, err := repository.Create(context.Background(), owner, draft, key); err != nil {
		t.Fatalf("create: %v", err)
	}
	draft.Merchant = "Changed"
	if _, err := repository.Create(context.Background(), owner, draft, key); !errors.Is(err, ErrIdempotencyConflict) {
		t.Fatalf("expected conflict, got %v", err)
	}
}

func TestRepositoryEnforcesOwnerAndVersionOnMutation(t *testing.T) {
	pool := purchaseTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	other := auth.UserID("33333333-3333-4333-8333-333333333333")
	insertPurchaseUser(t, pool, owner)
	insertPurchaseUser(t, pool, other)
	repository := NewPostgresRepository(pool)
	created, err := repository.Create(context.Background(), owner, validQuickDraft(), "44444444-4444-4444-8444-444444444444")
	if err != nil {
		t.Fatal(err)
	}
	created.Merchant = "Updated"
	if _, err = repository.Update(context.Background(), other, created, 1); !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected forbidden update, got %v", err)
	}
	updated, err := repository.Update(context.Background(), owner, created, 1)
	if err != nil {
		t.Fatalf("update: %v", err)
	}
	if updated.Version != 2 || updated.Merchant != "Updated" {
		t.Fatalf("unexpected update: %+v", updated)
	}
	if _, err = repository.Update(context.Background(), owner, updated, 1); !errors.Is(err, ErrVersionConflict) {
		t.Fatalf("expected version conflict, got %v", err)
	}
	if err = repository.Delete(context.Background(), other, updated.ID, 2); !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected forbidden delete, got %v", err)
	}
	if err = repository.Delete(context.Background(), owner, updated.ID, 2); err != nil {
		t.Fatalf("delete: %v", err)
	}
}

func purchaseTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool := testutil.EmptyPool(t)
	if err := postgres.Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatal(err)
	}
	return pool
}
func insertPurchaseUser(t *testing.T, pool *pgxpool.Pool, id auth.UserID) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), "insert into users(id) values($1)", id); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(context.Background(), "insert into profiles(id) values($1)", id); err != nil {
		t.Fatal(err)
	}
}
