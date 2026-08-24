package postgres

import (
	"context"
	"errors"
	"testing"

	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5"
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
	if count != 1 {
		t.Fatalf("expected one applied migration, got %d", count)
	}
}

func TestMigrateDownRevertsLatestMigration(t *testing.T) {
	pool := migrationTestPool(t)
	resetPublicSchema(t, pool)

	if err := Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate up: %v", err)
	}
	if err := Down(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate down: %v", err)
	}

	var ignored string
	err := pool.QueryRow(context.Background(), "select id from users limit 1").Scan(&ignored)
	if !errors.Is(err, pgx.ErrNoRows) && err == nil {
		t.Fatal("expected users table to be removed")
	}
	if err == nil || errors.Is(err, pgx.ErrNoRows) {
		t.Fatal("expected querying removed users table to fail")
	}
}
