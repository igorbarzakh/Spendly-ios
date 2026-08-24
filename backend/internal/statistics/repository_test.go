package statistics

import (
	"context"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5/pgxpool"
	"testing"
	"time"
)

func TestMonthlyTotalsIncludeQuickAndDetailedItems(t *testing.T) {
	pool := statsDB(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	insertStatsUser(t, pool, user)
	p := purchases.NewPostgresRepository(pool)
	quick := statsQuick("22222222-2222-4222-8222-222222222222", 100, "Food")
	if _, e := p.Create(context.Background(), user, quick, "33333333-3333-4333-8333-333333333333"); e != nil {
		t.Fatal(e)
	}
	detailed := statsQuick("44444444-4444-4444-8444-444444444444", 0, "")
	detailed.Kind = purchases.KindDetailed
	detailed.Items = []purchases.ItemDraft{{ID: "55555555-5555-4555-8555-555555555555", Position: 0, Name: "Taxi", Category: "Transport", AmountMinor: 75}}
	if _, e := p.Create(context.Background(), user, detailed, "66666666-6666-4666-8666-666666666666"); e != nil {
		t.Fatal(e)
	}
	result, e := NewService(NewPostgresRepository(pool)).Monthly(context.Background(), user, purchases.Scope{}, time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC))
	if e != nil {
		t.Fatal(e)
	}
	if result.TotalMinor != 175 || result.ByCategory["Food"] != 100 || result.ByCategory["Transport"] != 75 || result.ByDay["2026-08-24"] != 175 {
		t.Fatalf("unexpected stats %+v", result)
	}
	if err := p.Delete(context.Background(), user, quick.ID, 1); err != nil {
		t.Fatal(err)
	}
	result, e = NewService(NewPostgresRepository(pool)).Monthly(context.Background(), user, purchases.Scope{}, time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC), time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC))
	if e != nil || result.TotalMinor != 75 {
		t.Fatalf("deleted purchase affected stats: %+v %v", result, e)
	}
}

func TestMonthlyGroupScopeRequiresMembership(t *testing.T) {
	pool := statsDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	member := auth.UserID("22222222-2222-4222-8222-222222222222")
	outsider := auth.UserID("33333333-3333-4333-8333-333333333333")
	for _, user := range []auth.UserID{owner, member, outsider} {
		insertStatsUser(t, pool, user)
	}
	groupID := "44444444-4444-4444-8444-444444444444"
	if _, err := pool.Exec(context.Background(), "insert into groups(id,name,owner_id) values($1,'Family',$2)", groupID, owner); err != nil {
		t.Fatal(err)
	}
	if _, err := pool.Exec(context.Background(), "insert into group_members(group_id,user_id,role) values($1,$2,'member')", groupID, member); err != nil {
		t.Fatal(err)
	}
	draft := statsQuick("55555555-5555-4555-8555-555555555555", 100, "Food")
	draft.GroupID = &groupID
	if _, err := purchases.NewPostgresRepository(pool).Create(context.Background(), owner, draft, "66666666-6666-4666-8666-666666666666"); err != nil {
		t.Fatal(err)
	}
	service := NewService(NewPostgresRepository(pool))
	from := time.Date(2026, 8, 1, 0, 0, 0, 0, time.UTC)
	to := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	memberResult, err := service.Monthly(context.Background(), member, purchases.Scope{GroupID: &groupID}, from, to)
	if err != nil || memberResult.TotalMinor != 100 {
		t.Fatalf("member group stats: %+v %v", memberResult, err)
	}
	outsiderResult, err := service.Monthly(context.Background(), outsider, purchases.Scope{GroupID: &groupID}, from, to)
	if err != nil || outsiderResult.TotalMinor != 0 {
		t.Fatalf("outsider group stats: %+v %v", outsiderResult, err)
	}
}
func statsQuick(id string, amount int64, category string) purchases.Draft {
	return purchases.Draft{ID: id, Kind: purchases.KindQuick, Merchant: "M", Category: category, AmountMinor: amount, CurrencyCode: "RUB", SpentAt: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC), LocalDate: "2026-08-24", TimeZone: "Europe/Moscow"}
}
func statsDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool := testutil.EmptyPool(t)
	if err := postgres.Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatal(err)
	}
	return pool
}
func insertStatsUser(t *testing.T, p *pgxpool.Pool, u auth.UserID) {
	if _, e := p.Exec(context.Background(), "insert into users(id)values($1)", u); e != nil {
		t.Fatal(e)
	}
	if _, e := p.Exec(context.Background(), "insert into profiles(id)values($1)", u); e != nil {
		t.Fatal(e)
	}
}
