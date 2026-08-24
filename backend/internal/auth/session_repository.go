package auth

import (
	"context"
	"errors"
	"fmt"
	"time"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

type SessionRepository struct {
	pool *pgxpool.Pool
}

func NewSessionRepository(pool *pgxpool.Pool) *SessionRepository {
	return &SessionRepository{pool: pool}
}

func (repository *SessionRepository) Create(ctx context.Context, session SessionRecord) error {
	_, err := repository.pool.Exec(ctx, `
		insert into user_sessions(id, family_id, user_id, token_hash, expires_at, created_at)
		values ($1, $2, $3, $4, $5, $6)
	`, session.ID, session.FamilyID, session.UserID, session.TokenHash[:], session.ExpiresAt, session.CreatedAt)
	return err
}

func (repository *SessionRepository) Rotate(
	ctx context.Context,
	currentHash [32]byte,
	next SessionRecord,
	now time.Time,
) (UserID, error) {
	tx, err := repository.pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return "", err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	var currentID SessionID
	var familyID string
	var userID UserID
	var expiresAt time.Time
	var usedAt, revokedAt *time.Time
	err = tx.QueryRow(ctx, `
		select id, family_id, user_id, expires_at, used_at, revoked_at
		from user_sessions
		where token_hash = $1
		for update
	`, currentHash[:]).Scan(&currentID, &familyID, &userID, &expiresAt, &usedAt, &revokedAt)
	if errors.Is(err, pgx.ErrNoRows) {
		return "", ErrInvalidRefreshToken
	}
	if err != nil {
		return "", err
	}

	if usedAt != nil {
		if _, err := tx.Exec(ctx, `
			update user_sessions set revoked_at = coalesce(revoked_at, $2)
			where family_id = $1
		`, familyID, now); err != nil {
			return "", err
		}
		if err := tx.Commit(ctx); err != nil {
			return "", err
		}
		return "", ErrRefreshReuse
	}
	if revokedAt != nil || !expiresAt.After(now) {
		return "", ErrInvalidRefreshToken
	}

	next.UserID = userID
	next.FamilyID = familyID
	if _, err := tx.Exec(ctx, `
		insert into user_sessions(id, family_id, user_id, token_hash, expires_at, created_at)
		values ($1, $2, $3, $4, $5, $6)
	`, next.ID, next.FamilyID, next.UserID, next.TokenHash[:], next.ExpiresAt, next.CreatedAt); err != nil {
		return "", err
	}
	if _, err := tx.Exec(ctx, `
		update user_sessions
		set used_at = $2, replaced_by_session_id = $3
		where id = $1
	`, currentID, now, next.ID); err != nil {
		return "", err
	}
	if err := tx.Commit(ctx); err != nil {
		return "", err
	}
	return userID, nil
}

func (repository *SessionRepository) Revoke(ctx context.Context, hash [32]byte, now time.Time) error {
	_, err := repository.pool.Exec(ctx, `
		update user_sessions set revoked_at = coalesce(revoked_at, $2)
		where token_hash = $1
	`, hash[:], now)
	return err
}

func (repository *SessionRepository) RevokeAll(ctx context.Context, userID UserID, now time.Time) error {
	result, err := repository.pool.Exec(ctx, `
		update user_sessions set revoked_at = coalesce(revoked_at, $2)
		where user_id = $1
	`, userID, now)
	if err != nil {
		return err
	}
	if result.RowsAffected() == 0 {
		return fmt.Errorf("revoke sessions: %w", ErrInvalidRefreshToken)
	}
	return nil
}
