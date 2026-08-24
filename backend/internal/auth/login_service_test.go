package auth

import (
	"context"
	"errors"
	"testing"
)

type identityVerifierFunc func(context.Context, string, string) (Identity, error)

func (verifier identityVerifierFunc) Verify(ctx context.Context, token, nonce string) (Identity, error) {
	return verifier(ctx, token, nonce)
}

func TestInvalidProviderTokenDoesNotCreateUser(t *testing.T) {
	pool, _ := authTestDatabase(t)
	var usersBefore int
	if err := pool.QueryRow(context.Background(), "select count(*) from users").Scan(&usersBefore); err != nil {
		t.Fatalf("count users before sign-in: %v", err)
	}
	service := NewAuthService(map[Provider]IdentityVerifier{
		ProviderGoogle: identityVerifierFunc(func(context.Context, string, string) (Identity, error) {
			return Identity{}, ErrInvalidIdentityToken
		}),
	}, NewIdentityRepository(pool), nil)

	_, _, err := service.SignIn(context.Background(), ProviderGoogle, "invalid", "nonce")
	if !errors.Is(err, ErrInvalidIdentityToken) {
		t.Fatalf("expected invalid token, got %v", err)
	}
	var usersAfter int
	if err := pool.QueryRow(context.Background(), "select count(*) from users").Scan(&usersAfter); err != nil {
		t.Fatalf("count users after sign-in: %v", err)
	}
	if usersAfter != usersBefore {
		t.Fatalf("invalid token created a user: before=%d after=%d", usersBefore, usersAfter)
	}
}
