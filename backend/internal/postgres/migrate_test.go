package postgres

import (
	"context"
	"errors"
	"os"
	"testing"

	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
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

func migrationTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	url := os.Getenv("TEST_DATABASE_URL")
	if url == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	pool, err := pgxpool.New(context.Background(), url)
	if err != nil {
		t.Fatalf("create pool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("ping database: %v", err)
	}
	return pool
}

func resetPublicSchema(t *testing.T, pool *pgxpool.Pool) {
	t.Helper()
	if _, err := pool.Exec(context.Background(), "drop schema if exists public cascade; create schema public"); err != nil {
		t.Fatalf("reset public schema: %v", err)
	}
}
