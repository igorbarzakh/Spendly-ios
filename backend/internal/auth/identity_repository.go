package auth

import (
	"context"
	"errors"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type User struct {
	ID           UserID `json:"id"`
	DisplayName  string `json:"display_name,omitempty"`
	CurrencyCode string `json:"currency_code,omitempty"`
	TimeZone     string `json:"time_zone,omitempty"`
}

type IdentityRepository struct{ pool *pgxpool.Pool }

func NewIdentityRepository(pool *pgxpool.Pool) *IdentityRepository {
	return &IdentityRepository{pool: pool}
}

func (repository *IdentityRepository) FindOrCreate(ctx context.Context, identity Identity) (User, bool, error) {
	if (identity.Provider != ProviderApple && identity.Provider != ProviderGoogle) || identity.Subject == "" {
		return User{}, false, ErrInvalidIdentityToken
	}
	if user, err := repository.find(ctx, repository.pool, identity); err == nil {
		return user, false, nil
	} else if !errors.Is(err, pgx.ErrNoRows) {
		return User{}, false, err
	}
	userID, err := newUUID()
	if err != nil {
		return User{}, false, err
	}
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return User{}, false, err
	}
	defer func() { _ = tx.Rollback(ctx) }()
	now := time.Now().UTC()
	if _, err = tx.Exec(ctx, "insert into users(id, created_at, updated_at) values ($1, $2, $2)", userID, now); err != nil {
		return User{}, false, err
	}
	if _, err = tx.Exec(ctx, "insert into profiles(id, display_name, created_at, updated_at) values ($1, nullif($2, ''), $3, $3)", userID, identity.Name, now); err != nil {
		return User{}, false, err
	}
	if _, err = tx.Exec(ctx, `insert into user_identities(user_id, provider, provider_subject, email_at_link, created_at, updated_at) values ($1,$2,$3,nullif($4,''),$5,$5)`, userID, identity.Provider, identity.Subject, identity.Email, now); err != nil {
		_ = tx.Rollback(ctx)
		if user, findErr := repository.find(ctx, repository.pool, identity); findErr == nil {
			return user, false, nil
		}
		return User{}, false, err
	}
	if err = tx.Commit(ctx); err != nil {
		return User{}, false, err
	}
	return User{ID: UserID(userID), DisplayName: identity.Name, CurrencyCode: "RUB", TimeZone: "Europe/Moscow"}, true, nil
}

type identityQueryer interface {
	QueryRow(context.Context, string, ...any) pgx.Row
}

func (repository *IdentityRepository) find(ctx context.Context, queryer identityQueryer, identity Identity) (User, error) {
	var user User
	err := queryer.QueryRow(ctx, `select u.id, coalesce(p.display_name,''), p.currency_code, p.time_zone from user_identities i join users u on u.id=i.user_id join profiles p on p.id=u.id where i.provider=$1 and i.provider_subject=$2`, identity.Provider, identity.Subject).Scan(&user.ID, &user.DisplayName, &user.CurrencyCode, &user.TimeZone)
	return user, err
}
