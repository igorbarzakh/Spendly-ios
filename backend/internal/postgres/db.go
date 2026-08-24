package postgres

import (
	"context"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgconn"
	"github.com/jackc/pgx/v5/pgxpool"
)

type DBTX interface {
	Exec(context.Context, string, ...any) (pgconn.CommandTag, error)
	Query(context.Context, string, ...any) (pgx.Rows, error)
	QueryRow(context.Context, string, ...any) pgx.Row
}

type Transactor interface {
	WithinTransaction(context.Context, func(context.Context, DBTX) error) error
}

type DB struct {
	pool *pgxpool.Pool
}

func NewDB(pool *pgxpool.Pool) *DB {
	return &DB{pool: pool}
}

func (database *DB) Ping(ctx context.Context) error {
	return database.pool.Ping(ctx)
}

func (database *DB) WithinTransaction(ctx context.Context, run func(context.Context, DBTX) error) error {
	tx, err := database.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if err := run(ctx, tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}
