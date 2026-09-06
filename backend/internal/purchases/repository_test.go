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
	query := ListQuery{From: draft.SpentAt.Add(-time.Second), To: draft.SpentAt.Add(time.Second), Limit: 50}
	visible, err := repository.List(context.Background(), owner, Scope{}, query)
	if err != nil || len(visible) != 1 {
		t.Fatalf("owner list: %d %v", len(visible), err)
	}
	hidden, err := repository.List(context.Background(), other, Scope{}, query)
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

func TestRepositoryCreateNormalizesDetailedItemTotals(t *testing.T) {
	pool := purchaseTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	insertPurchaseUser(t, pool, owner)
	repository := NewPostgresRepository(pool)
	draft := validDetailedCartDraft()
	draft.Items[0].AmountMinor = 1

	created, err := repository.Create(context.Background(), owner, draft, "44444444-4444-4444-8444-444444444444")

	if err != nil {
		t.Fatalf("create: %v", err)
	}
	if created.Items[0].AmountMinor != 19000 {
		t.Fatalf("expected normalized item total, got %d", created.Items[0].AmountMinor)
	}
	if created.TotalAmountMinor != 43500 {
		t.Fatalf("expected derived purchase total, got %d", created.TotalAmountMinor)
	}
}

func TestRepositoryListUsesStableCursorOrder(t *testing.T) {
	pool := purchaseTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	insertPurchaseUser(t, pool, owner)
	repository := NewPostgresRepository(pool)
	service := NewService(repository)
	spentAt := time.Date(2026, 9, 7, 12, 0, 0, 0, time.UTC)
	ids := []string{
		"11111111-1111-4111-8111-111111111112",
		"22222222-2222-4222-8222-222222222222",
		"33333333-3333-4333-8333-333333333333",
	}
	keys := []string{
		"44444444-4444-4444-8444-444444444444",
		"44444444-4444-4444-8444-444444444445",
		"44444444-4444-4444-8444-444444444446",
	}
	for index, id := range ids {
		draft := validQuickDraft()
		draft.ID = id
		draft.SpentAt = spentAt
		if _, err := repository.Create(context.Background(), owner, draft, keys[index]); err != nil {
			t.Fatalf("create purchase %s: %v", id, err)
		}
	}

	first, err := service.List(context.Background(), owner, Scope{}, ListOptions{Limit: 2})
	if err != nil {
		t.Fatalf("first page: %v", err)
	}
	second, err := service.List(context.Background(), owner, Scope{}, ListOptions{Limit: 2, Cursor: first.NextCursor})
	if err != nil {
		t.Fatalf("second page: %v", err)
	}

	got := []string{first.Purchases[0].ID, first.Purchases[1].ID, second.Purchases[0].ID}
	want := []string{ids[2], ids[1], ids[0]}
	for index := range want {
		if got[index] != want[index] {
			t.Fatalf("unexpected order: got %v want %v", got, want)
		}
	}
	if !first.HasMore || second.HasMore || second.NextCursor != "" {
		t.Fatalf("unexpected page metadata: first=%+v second=%+v", first, second)
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
