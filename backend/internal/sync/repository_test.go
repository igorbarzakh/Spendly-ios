package sync

import (
	"context"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestChangesAreStableAndIncludeTombstones(t *testing.T) {
	pool := syncDB(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	insertSyncUser(t, pool, user)
	purchaseRepository := purchases.NewPostgresRepository(pool)
	service := NewService(NewPostgresRepository(pool), []byte("01234567890123456789012345678901"))

	first := syncDetailed("22222222-2222-4222-8222-222222222222")
	if _, err := purchaseRepository.Create(context.Background(), user, first, "33333333-3333-4333-8333-333333333333"); err != nil {
		t.Fatal(err)
	}
	firstPage, err := service.Page(context.Background(), user, purchases.Scope{}, "", 1)
	if err != nil || len(firstPage.Changes) != 1 || firstPage.Changes[0].Purchase.ID != first.ID {
		t.Fatalf("unexpected first page: %+v %v", firstPage, err)
	}
	if len(firstPage.Changes[0].Purchase.Items) != 1 || firstPage.Changes[0].Purchase.TotalAmountMinor != 100 {
		t.Fatalf("detailed purchase was not hydrated: %+v", firstPage.Changes[0])
	}

	second := syncQuick("44444444-4444-4444-8444-444444444444")
	created, err := purchaseRepository.Create(context.Background(), user, second, "55555555-5555-4555-8555-555555555555")
	if err != nil {
		t.Fatal(err)
	}
	if err = purchaseRepository.Delete(context.Background(), user, created.ID, created.Version); err != nil {
		t.Fatal(err)
	}
	secondPage, err := service.Page(context.Background(), user, purchases.Scope{}, firstPage.NextCursor, 10)
	if err != nil || len(secondPage.Changes) != 1 {
		t.Fatalf("unexpected second page: %+v %v", secondPage, err)
	}
	change := secondPage.Changes[0]
	if change.Purchase.ID != second.ID || !change.Deleted || change.Purchase.DeletedAt == nil {
		t.Fatalf("expected tombstone, got %+v", change)
	}

	third := syncQuick("88888888-8888-4888-8888-888888888888")
	if _, err = purchaseRepository.Create(context.Background(), user, third, "99999999-9999-4999-8999-999999999999"); err != nil {
		t.Fatal(err)
	}
	thirdPage, err := service.Page(context.Background(), user, purchases.Scope{}, secondPage.NextCursor, 10)
	if err != nil || len(thirdPage.Changes) != 1 || thirdPage.Changes[0].Purchase.TotalAmountMinor != 100 {
		t.Fatalf("quick total was not hydrated: %+v %v", thirdPage, err)
	}
}

func syncDetailed(id string) purchases.Draft {
	draft := syncQuick(id)
	draft.Kind = purchases.KindDetailed
	draft.Category = ""
	draft.AmountMinor = 0
	draft.Items = []purchases.ItemDraft{{
		ID: "77777777-7777-4777-8777-777777777777", Position: 0,
		Name: "Groceries", Category: "Food", AmountMinor: 100,
	}}
	return draft
}

func syncQuick(id string) purchases.Draft {
	return purchases.Draft{
		ID: id, Kind: purchases.KindQuick, Merchant: "Market", Category: "Food",
		AmountMinor: 100, CurrencyCode: "RUB", SpentAt: time.Now().UTC(),
		LocalDate: time.Now().UTC().Format("2006-01-02"), TimeZone: "UTC",
	}
}

func syncDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool := testutil.EmptyPool(t)
	if err := postgres.Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatal(err)
	}
	return pool
}

func insertSyncUser(t *testing.T, pool *pgxpool.Pool, user auth.UserID) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), "insert into users(id) values($1)", user); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(context.Background(), "insert into profiles(id) values($1)", user); err != nil {
		t.Fatal(err)
	}
}
