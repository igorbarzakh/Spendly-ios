package purchases

import (
	"bytes"
	"context"
	"crypto/sha256"
	"encoding/json"
	"errors"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type PostgresRepository struct{ pool *pgxpool.Pool }

func NewPostgresRepository(pool *pgxpool.Pool) *PostgresRepository {
	return &PostgresRepository{pool: pool}
}

func (repository *PostgresRepository) Create(ctx context.Context, owner auth.UserID, draft Draft, key string) (Purchase, error) {
	payload, err := json.Marshal(draft)
	if err != nil {
		return Purchase{}, err
	}
	hash := sha256.Sum256(payload)
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Purchase{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var storedHash, storedBody []byte
	err = tx.QueryRow(ctx, "select request_hash, response_body from idempotency_keys where user_id=$1 and key=$2 for update", owner, key).Scan(&storedHash, &storedBody)
	if err == nil {
		if !bytes.Equal(storedHash, hash[:]) {
			return Purchase{}, ErrIdempotencyConflict
		}
		var saved Purchase
		if json.Unmarshal(storedBody, &saved) != nil {
			return Purchase{}, ErrIdempotencyConflict
		}
		return saved, nil
	}
	if !errors.Is(err, pgx.ErrNoRows) {
		return Purchase{}, err
	}
	if draft.GroupID != nil {
		var allowed bool
		if err = tx.QueryRow(ctx, `select exists(select 1 from group_members m join groups g on g.id=m.group_id where m.group_id=$1 and m.user_id=$2 and g.archived_at is null)`, *draft.GroupID, owner).Scan(&allowed); err != nil {
			return Purchase{}, err
		}
		if !allowed {
			return Purchase{}, ErrForbidden
		}
	}
	var category any
	var amount any
	if draft.Kind == KindQuick {
		category, amount = draft.Category, draft.AmountMinor
	}
	now := time.Now().UTC()
	_, err = tx.Exec(ctx, `insert into purchases(id,owner_id,group_id,kind,merchant,category,amount_minor,currency_code,spent_at,local_date,time_zone,created_at,updated_at) values($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$12)`, draft.ID, owner, draft.GroupID, draft.Kind, draft.Merchant, category, amount, draft.CurrencyCode, draft.SpentAt, draft.LocalDate, draft.TimeZone, now)
	if err != nil {
		return Purchase{}, err
	}
	for _, item := range draft.Items {
		if _, err = tx.Exec(ctx, `insert into purchase_items(id,purchase_id,position,name,category,amount_minor,created_at,updated_at) values($1,$2,$3,$4,$5,$6,$7,$7)`, item.ID, draft.ID, item.Position, item.Name, item.Category, item.AmountMinor, now); err != nil {
			return Purchase{}, err
		}
	}
	total, _ := draft.TotalMinor()
	purchase := Purchase{Draft: draft, OwnerID: owner, Version: 1, TotalAmountMinor: total, CreatedAt: now, UpdatedAt: now}
	body, _ := json.Marshal(purchase)
	_, err = tx.Exec(ctx, `insert into idempotency_keys(user_id,key,request_hash,response_status,response_body,expires_at) values($1,$2,$3,201,$4,$5)`, owner, key, hash[:], body, now.Add(24*time.Hour))
	if err != nil {
		return Purchase{}, err
	}
	if err = tx.Commit(ctx); err != nil {
		return Purchase{}, err
	}
	return purchase, nil
}

func (repository *PostgresRepository) List(ctx context.Context, user auth.UserID, scope Scope, from, to time.Time) ([]Purchase, error) {
	query := `select p.id,p.group_id,p.kind,p.merchant,coalesce(p.category,''),coalesce(p.amount_minor,0),p.currency_code,p.spent_at,p.local_date::text,p.time_zone,p.owner_id,p.version,p.created_at,p.updated_at,p.deleted_at from purchases p where p.deleted_at is null and p.spent_at >= $2 and p.spent_at < $3 and `
	args := []any{user, from, to}
	if scope.GroupID == nil {
		query += `p.owner_id=$1`
	} else {
		query += `p.group_id=$4 and exists(select 1 from group_members where group_id=$4 and user_id=$1)`
		args = append(args, *scope.GroupID)
	}
	query += ` order by p.spent_at desc,p.id`
	rows, err := repository.pool.Query(ctx, query, args...)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var result []Purchase
	for rows.Next() {
		var p Purchase
		if err = rows.Scan(&p.ID, &p.GroupID, &p.Kind, &p.Merchant, &p.Category, &p.AmountMinor, &p.CurrencyCode, &p.SpentAt, &p.LocalDate, &p.TimeZone, &p.OwnerID, &p.Version, &p.CreatedAt, &p.UpdatedAt, &p.DeletedAt); err != nil {
			return nil, err
		}
		if p.Kind == KindDetailed {
			itemRows, e := repository.pool.Query(ctx, `select id,position,name,category,amount_minor,created_at,updated_at from purchase_items where purchase_id=$1 order by position`, p.ID)
			if e != nil {
				return nil, e
			}
			for itemRows.Next() {
				var item ItemDraft
				var createdAt, updatedAt time.Time
				if e = itemRows.Scan(&item.ID, &item.Position, &item.Name, &item.Category, &item.AmountMinor, &createdAt, &updatedAt); e != nil {
					itemRows.Close()
					return nil, e
				}
				p.Items = append(p.Items, item)
			}
			itemRows.Close()
		}
		p.TotalAmountMinor, _ = p.TotalMinor()
		result = append(result, p)
	}
	return result, rows.Err()
}

func (repository *PostgresRepository) Update(ctx context.Context, user auth.UserID, purchase Purchase, expected int64) (Purchase, error) {
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return Purchase{}, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	owner, group, version, err := lockedPurchase(ctx, tx, purchase.ID)
	if err != nil {
		return Purchase{}, err
	}
	allowed, err := canMutate(ctx, tx, user, owner, group)
	if err != nil {
		return Purchase{}, err
	}
	if !allowed {
		return Purchase{}, ErrForbidden
	}
	if version != expected {
		return Purchase{}, ErrVersionConflict
	}
	purchase.OwnerID = owner
	var category any
	var amount any
	if purchase.Kind == KindQuick {
		category, amount = purchase.Category, purchase.AmountMinor
	}
	_, err = tx.Exec(ctx, `update purchases set group_id=$2,kind=$3,merchant=$4,category=$5,amount_minor=$6,currency_code=$7,spent_at=$8,local_date=$9,time_zone=$10 where id=$1`, purchase.ID, purchase.GroupID, purchase.Kind, purchase.Merchant, category, amount, purchase.CurrencyCode, purchase.SpentAt, purchase.LocalDate, purchase.TimeZone)
	if err != nil {
		return Purchase{}, err
	}
	if _, err = tx.Exec(ctx, "delete from purchase_items where purchase_id=$1", purchase.ID); err != nil {
		return Purchase{}, err
	}
	now := time.Now().UTC()
	for _, item := range purchase.Items {
		if _, err = tx.Exec(ctx, `insert into purchase_items(id,purchase_id,position,name,category,amount_minor,created_at,updated_at) values($1,$2,$3,$4,$5,$6,$7,$7)`, item.ID, purchase.ID, item.Position, item.Name, item.Category, item.AmountMinor, now); err != nil {
			return Purchase{}, err
		}
	}
	if err = tx.Commit(ctx); err != nil {
		return Purchase{}, err
	}
	purchase.Version = version + 1
	purchase.UpdatedAt = now
	purchase.TotalAmountMinor, _ = purchase.TotalMinor()
	return purchase, nil
}

func (repository *PostgresRepository) Delete(ctx context.Context, user auth.UserID, id string, expected int64) error {
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	owner, group, version, err := lockedPurchase(ctx, tx, id)
	if err != nil {
		return err
	}
	allowed, err := canMutate(ctx, tx, user, owner, group)
	if err != nil {
		return err
	}
	if !allowed {
		return ErrForbidden
	}
	if version != expected {
		return ErrVersionConflict
	}
	result, err := tx.Exec(ctx, "update purchases set deleted_at=now() where id=$1 and deleted_at is null", id)
	if err != nil {
		return err
	}
	if result.RowsAffected() != 1 {
		return ErrNotFound
	}
	return tx.Commit(ctx)
}

func lockedPurchase(ctx context.Context, tx pgx.Tx, id string) (auth.UserID, *string, int64, error) {
	var owner auth.UserID
	var group *string
	var version int64
	err := tx.QueryRow(ctx, "select owner_id,group_id,version from purchases where id=$1 and deleted_at is null for update", id).Scan(&owner, &group, &version)
	if errors.Is(err, pgx.ErrNoRows) {
		err = ErrNotFound
	}
	return owner, group, version, err
}
func canMutate(ctx context.Context, tx pgx.Tx, user, owner auth.UserID, group *string) (bool, error) {
	if user == owner {
		return true, nil
	}
	if group == nil {
		return false, nil
	}
	var allowed bool
	err := tx.QueryRow(ctx, `select exists(select 1 from group_members m join groups g on g.id=m.group_id where m.group_id=$1 and m.user_id=$2 and g.archived_at is null and (m.role='owner' or m.can_manage_expenses))`, *group, user).Scan(&allowed)
	return allowed, err
}
