package postgres

import (
	"context"
	"errors"
	"testing"
)

func TestWithinTransactionCommitsOnSuccess(t *testing.T) {
	pool := migrationTestPool(t)
	prepareTransactionProbe(t, pool)
	database := NewDB(pool)

	err := database.WithinTransaction(context.Background(), func(ctx context.Context, tx DBTX) error {
		_, err := tx.Exec(ctx, "insert into transaction_probe(value) values ($1)", "committed")
		return err
	})
	if err != nil {
		t.Fatalf("run transaction: %v", err)
	}

	var count int
	if err := pool.QueryRow(context.Background(), "select count(*) from transaction_probe where value = 'committed'").Scan(&count); err != nil {
		t.Fatalf("count rows: %v", err)
	}
	if count != 1 {
		t.Fatalf("expected committed row, got %d", count)
	}
}

func TestWithinTransactionRollsBackOnError(t *testing.T) {
	pool := migrationTestPool(t)
	prepareTransactionProbe(t, pool)
	database := NewDB(pool)
	wantErr := errors.New("reject transaction")

	err := database.WithinTransaction(context.Background(), func(ctx context.Context, tx DBTX) error {
		if _, err := tx.Exec(ctx, "insert into transaction_probe(value) values ($1)", "rolled back"); err != nil {
			return err
		}
		return wantErr
	})
	if !errors.Is(err, wantErr) {
		t.Fatalf("expected callback error, got %v", err)
	}

	var count int
	if err := pool.QueryRow(context.Background(), "select count(*) from transaction_probe").Scan(&count); err != nil {
		t.Fatalf("count rows: %v", err)
	}
	if count != 0 {
		t.Fatalf("expected rollback, found %d rows", count)
	}
}

func TestWithinTransactionHonorsCancelledContext(t *testing.T) {
	pool := migrationTestPool(t)
	database := NewDB(pool)
	ctx, cancel := context.WithCancel(context.Background())
	cancel()

	err := database.WithinTransaction(ctx, func(ctx context.Context, tx DBTX) error {
		_, err := tx.Exec(ctx, "select pg_sleep(10)")
		return err
	})
	if !errors.Is(err, context.Canceled) {
		t.Fatalf("expected context cancellation, got %v", err)
	}
}

func prepareTransactionProbe(t *testing.T, database DBTX) {
	t.Helper()
	if _, err := database.Exec(context.Background(), "drop table if exists transaction_probe; create table transaction_probe(value text not null)"); err != nil {
		t.Fatalf("prepare transaction probe: %v", err)
	}
}
