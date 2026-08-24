package postgres

import (
	"testing"

	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/jackc/pgx/v5/pgxpool"
)

func migrationTestPool(t *testing.T) *pgxpool.Pool {
	t.Helper()
	return testutil.EmptyPool(t)
}

func resetPublicSchema(t *testing.T, _ *pgxpool.Pool) {
	t.Helper()
}
