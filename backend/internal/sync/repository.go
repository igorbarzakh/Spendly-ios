package sync

import (
	"context"

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

func (repository *PostgresRepository) Changes(ctx context.Context, user auth.UserID, scope purchases.Scope, cursor Cursor, limit int) ([]Change, error) {
	visibility := "p.owner_id = $1"
	arguments := []any{user, cursor.UpdatedAt, cursor.ID, limit}
	if scope.GroupID != nil {
		visibility = `p.group_id = $5 and exists (
			select 1 from group_members m
			where m.group_id = $5 and m.user_id = $1
		)`
		arguments = append(arguments, *scope.GroupID)
	}

	query := `select p.id,p.group_id,p.kind,p.merchant,coalesce(p.category,''),
		coalesce(p.amount_minor,0),p.currency_code,p.spent_at,p.local_date::text,
		p.time_zone,p.owner_id,p.version,p.created_at,p.updated_at,p.deleted_at
		from purchases p
		where (p.updated_at, p.id) > ($2, $3::uuid) and ` + visibility + `
		order by p.updated_at, p.id limit $4`
	rows, err := repository.pool.Query(ctx, query, arguments...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	changes := make([]Change, 0, limit)
	for rows.Next() {
		var purchase purchases.Purchase
		if err = rows.Scan(
			&purchase.ID, &purchase.GroupID, &purchase.Kind, &purchase.Merchant,
			&purchase.Category, &purchase.AmountMinor, &purchase.CurrencyCode,
			&purchase.SpentAt, &purchase.LocalDate, &purchase.TimeZone,
			&purchase.OwnerID, &purchase.Version, &purchase.CreatedAt,
			&purchase.UpdatedAt, &purchase.DeletedAt,
		); err != nil {
			return nil, err
		}
		changes = append(changes, Change{Purchase: purchase, Deleted: purchase.DeletedAt != nil})
	}
	if err = rows.Err(); err != nil {
		return nil, err
	}
	if err = repository.loadItems(ctx, changes); err != nil {
		return nil, err
	}
	return changes, nil
}

func (repository *PostgresRepository) loadItems(ctx context.Context, changes []Change) error {
	ids := make([]string, 0, len(changes))
	byID := make(map[string]int, len(changes))
	for index := range changes {
		purchase := &changes[index].Purchase
		if purchase.Kind == purchases.KindDetailed && purchase.DeletedAt == nil {
			ids = append(ids, purchase.ID)
			byID[purchase.ID] = index
		}
	}
	if len(ids) > 0 {
		rows, err := repository.pool.Query(ctx, `
			select purchase_id,id,position,name,category,amount_minor,created_at,updated_at
			from purchase_items where purchase_id = any($1::uuid[])
			order by purchase_id,position`, ids)
		if err != nil {
			return err
		}
		defer rows.Close()
		for rows.Next() {
			var purchaseID string
			var item purchases.Item
			if err = rows.Scan(&purchaseID, &item.ID, &item.Position, &item.Name, &item.Category, &item.AmountMinor, &item.CreatedAt, &item.UpdatedAt); err != nil {
				return err
			}
			index := byID[purchaseID]
			changes[index].Purchase.Items = append(changes[index].Purchase.Items, item.ItemDraft)
		}
		if err = rows.Err(); err != nil {
			return err
		}
	}
	for index := range changes {
		purchase := &changes[index].Purchase
		if purchase.DeletedAt == nil {
			purchase.TotalAmountMinor, _ = purchase.TotalMinor()
		}
	}
	return nil
}
