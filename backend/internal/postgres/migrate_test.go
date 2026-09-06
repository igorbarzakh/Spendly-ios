package postgres

import (
	"context"
	"testing"

	"github.com/igorbarzakh/spendly-ios/backend/migrations"
)

func TestMigrateFreshDatabase(t *testing.T) {
	pool := migrationTestPool(t)
	resetPublicSchema(t, pool)

	if err := Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate up: %v", err)
	}

	wantTables := []string{
		"schema_migrations",
		"users",
		"user_identities",
		"user_sessions",
		"profiles",
		"groups",
		"group_members",
		"group_invitations",
		"purchases",
		"purchase_items",
		"idempotency_keys",
	}
	for _, table := range wantTables {
		var exists bool
		err := pool.QueryRow(context.Background(), `
			select exists (
				select 1 from information_schema.tables
				where table_schema = 'public' and table_name = $1
			)
		`, table).Scan(&exists)
		if err != nil {
			t.Fatalf("look up table %s: %v", table, err)
		}
		if !exists {
			t.Errorf("expected table %s to exist", table)
		}
	}
}

func TestMigrateUpIsIdempotent(t *testing.T) {
	pool := migrationTestPool(t)
	resetPublicSchema(t, pool)

	if err := Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("first migrate up: %v", err)
	}
	if err := Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("second migrate up: %v", err)
	}

	var count int
	if err := pool.QueryRow(context.Background(), "select count(*) from schema_migrations").Scan(&count); err != nil {
		t.Fatalf("count migrations: %v", err)
	}
	available, err := readMigrations(migrations.Files)
	if err != nil {
		t.Fatalf("read migrations: %v", err)
	}
	if count != len(available) {
		t.Fatalf("expected %d applied migrations, got %d", len(available), count)
	}
}

func TestMigrateDownRevertsLatestMigration(t *testing.T) {
	pool := migrationTestPool(t)
	resetPublicSchema(t, pool)

	if err := Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	var latestVersion int64
	if err := pool.QueryRow(context.Background(), "select max(version) from schema_migrations").Scan(&latestVersion); err != nil {
		t.Fatalf("read latest migration: %v", err)
	}
	if latestVersion != 3 {
		t.Fatalf("expected pagination migration to be latest, got %d", latestVersion)
	}
	if err := Down(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate down: %v", err)
	}

	var stillApplied bool
	if err := pool.QueryRow(context.Background(), "select exists(select 1 from schema_migrations where version=$1)", latestVersion).Scan(&stillApplied); err != nil {
		t.Fatalf("check reverted migration: %v", err)
	}
	if stillApplied {
		t.Fatal("expected latest migration record to be removed")
	}
	var ownerIndex, groupIndex *string
	if err := pool.QueryRow(context.Background(), "select to_regclass('purchases_owner_spent_at_id_idx')::text, to_regclass('purchases_group_spent_at_id_idx')::text").Scan(&ownerIndex, &groupIndex); err != nil {
		t.Fatalf("check pagination indexes: %v", err)
	}
	if ownerIndex != nil || groupIndex != nil {
		t.Fatalf("expected pagination indexes to be removed: owner=%v group=%v", ownerIndex, groupIndex)
	}
}
