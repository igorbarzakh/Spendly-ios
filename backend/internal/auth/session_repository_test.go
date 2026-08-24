package auth

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5/pgxpool"
)

func TestSessionRepositoryStoresOnlyRefreshTokenHash(t *testing.T) {
	pool, userID := authTestDatabase(t)
	service := NewSessionService(NewSessionRepository(pool), testTokenManager(t, time.Now), 30*24*time.Hour, time.Now)

	tokens, err := service.Issue(context.Background(), userID)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	var storedHash []byte
	if err := pool.QueryRow(context.Background(), "select token_hash from user_sessions where user_id = $1", userID).Scan(&storedHash); err != nil {
		t.Fatalf("read stored token: %v", err)
	}
	want := HashRefreshToken(tokens.RefreshToken)
	if string(storedHash) != string(want[:]) {
		t.Fatal("database does not contain expected refresh token hash")
	}
	if string(storedHash) == tokens.RefreshToken {
		t.Fatal("raw refresh token was stored in database")
	}
}

func TestRefreshRotationRevokesFamilyOnReuse(t *testing.T) {
	pool, userID := authTestDatabase(t)
	service := NewSessionService(NewSessionRepository(pool), testTokenManager(t, time.Now), 30*24*time.Hour, time.Now)
	first, err := service.Issue(context.Background(), userID)
	if err != nil {
		t.Fatalf("issue first session: %v", err)
	}
	second, err := service.Refresh(context.Background(), first.RefreshToken)
	if err != nil {
		t.Fatalf("rotate refresh token: %v", err)
	}

	_, err = service.Refresh(context.Background(), first.RefreshToken)
	if !errors.Is(err, ErrRefreshReuse) {
		t.Fatalf("expected refresh reuse, got %v", err)
	}
	_, err = service.Refresh(context.Background(), second.RefreshToken)
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("expected family revocation, got %v", err)
	}
}

func TestLogoutRevokesCurrentSession(t *testing.T) {
	pool, userID := authTestDatabase(t)
	service := NewSessionService(NewSessionRepository(pool), testTokenManager(t, time.Now), 30*24*time.Hour, time.Now)
	tokens, err := service.Issue(context.Background(), userID)
	if err != nil {
		t.Fatalf("issue session: %v", err)
	}

	if err := service.Logout(context.Background(), tokens.RefreshToken); err != nil {
		t.Fatalf("logout: %v", err)
	}
	_, err = service.Refresh(context.Background(), tokens.RefreshToken)
	if !errors.Is(err, ErrInvalidRefreshToken) {
		t.Fatalf("expected revoked refresh token, got %v", err)
	}
}

func TestLogoutAllRevokesEveryUserSession(t *testing.T) {
	pool, userID := authTestDatabase(t)
	service := NewSessionService(NewSessionRepository(pool), testTokenManager(t, time.Now), 30*24*time.Hour, time.Now)
	first, _ := service.Issue(context.Background(), userID)
	second, _ := service.Issue(context.Background(), userID)

	if err := service.LogoutAll(context.Background(), userID); err != nil {
		t.Fatalf("logout all: %v", err)
	}
	for _, raw := range []string{first.RefreshToken, second.RefreshToken} {
		if _, err := service.Refresh(context.Background(), raw); !errors.Is(err, ErrInvalidRefreshToken) {
			t.Fatalf("expected revoked token, got %v", err)
		}
	}
}

func authTestDatabase(t *testing.T) (*pgxpool.Pool, UserID) {
	t.Helper()
	pool := testutil.EmptyPool(t)
	if err := postgres.Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatalf("migrate database: %v", err)
	}
	userID := UserID("11111111-1111-4111-8111-111111111111")
	if _, err := pool.Exec(context.Background(), "insert into users(id) values ($1)", userID); err != nil {
		t.Fatalf("insert user: %v", err)
	}
	return pool, userID
}
