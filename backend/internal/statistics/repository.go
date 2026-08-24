package statistics

import (
	"context"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
}

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (repository *PostgresRepository) Monthly(ctx context.Context, user auth.UserID, scope purchases.Scope, from, to time.Time) (MonthlyResult, error) {
	visibility := "p.owner_id = $1"
	arguments := []any{user, from, to}
	if scope.GroupID != nil {
		visibility = `p.group_id = $4 and exists (
			select 1 from group_members m
			where m.group_id = $4 and m.user_id = $1
		)`
		arguments = append(arguments, *scope.GroupID)
	}

	query := `
		with visible_amounts as (
			select p.local_date::text as day, p.category, p.amount_minor as amount
			from purchases p
			where p.deleted_at is null and p.kind = 'quick'
				and p.spent_at >= $2 and p.spent_at < $3 and ` + visibility + `
			union all
			select p.local_date::text as day, i.category, i.amount_minor as amount
			from purchases p
			join purchase_items i on i.purchase_id = p.id
			where p.deleted_at is null and p.kind = 'detailed'
				and p.spent_at >= $2 and p.spent_at < $3 and ` + visibility + `
		)
		select day, category, amount from visible_amounts`

	rows, err := repository.pool.Query(ctx, query, arguments...)
	if err != nil {
		return MonthlyResult{}, err
	}
	defer rows.Close()

	result := MonthlyResult{
		ByDay:      make(map[string]int64),
		ByCategory: make(map[string]int64),
	}
	for rows.Next() {
		var day, category string
		var amount int64
		if err = rows.Scan(&day, &category, &amount); err != nil {
			return MonthlyResult{}, err
		}
		result.TotalMinor += amount
		result.ByDay[day] += amount
		result.ByCategory[category] += amount
	}
	return result, rows.Err()
}
