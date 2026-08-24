package testutil

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"os"
	"testing"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

func EmptyPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	databaseURL := os.Getenv("TEST_DATABASE_URL")
	if databaseURL == "" {
		t.Skip("TEST_DATABASE_URL is not set")
	}

	adminConfig, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse admin database URL: %v", err)
	}
	adminConfig.ConnConfig.Database = "postgres"
	adminPool, err := pgxpool.NewWithConfig(context.Background(), adminConfig)
	if err != nil {
		t.Fatalf("create admin pool: %v", err)
	}
	t.Cleanup(adminPool.Close)

	database := "spendly_test_" + randomHex(t)
	databaseIdentifier := pgx.Identifier{database}.Sanitize()
	if _, err = adminPool.Exec(context.Background(), "create database "+databaseIdentifier); err != nil {
		t.Fatalf("create database: %v", err)
	}
	t.Cleanup(func() {
		if _, err := adminPool.Exec(context.Background(), "drop database if exists "+databaseIdentifier+" with (force)"); err != nil {
			t.Errorf("drop database %s: %v", database, err)
		}
	})

	config, err := pgxpool.ParseConfig(databaseURL)
	if err != nil {
		t.Fatalf("parse database URL: %v", err)
	}
	config.ConnConfig.Database = database

	pool, err := pgxpool.NewWithConfig(context.Background(), config)
	if err != nil {
		t.Fatalf("create test pool: %v", err)
	}
	t.Cleanup(pool.Close)
	if err := pool.Ping(context.Background()); err != nil {
		t.Fatalf("ping database: %v", err)
	}
	return pool
}

func randomHex(t *testing.T) string {
	t.Helper()
	var b [8]byte
	if _, err := rand.Read(b[:]); err != nil {
		t.Fatalf("generate schema suffix: %v", err)
	}
	return hex.EncodeToString(b[:])
}
