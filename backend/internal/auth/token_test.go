package auth

import (
	"crypto/ed25519"
	"crypto/rand"
	"errors"
	"testing"
	"time"
)

func TestAccessTokenRoundTrip(t *testing.T) {
	manager := testTokenManager(t, time.Now)

	raw, expiresAt, err := manager.IssueAccess(UserID("11111111-1111-4111-8111-111111111111"), SessionID("22222222-2222-4222-8222-222222222222"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	claims, err := manager.VerifyAccess(raw)
	if err != nil {
		t.Fatalf("verify access token: %v", err)
	}
	if claims.UserID != UserID("11111111-1111-4111-8111-111111111111") {
		t.Fatalf("unexpected user ID %q", claims.UserID)
	}
	if claims.SessionID != SessionID("22222222-2222-4222-8222-222222222222") {
		t.Fatalf("unexpected session ID %q", claims.SessionID)
	}
	if time.Until(expiresAt) <= 0 {
		t.Fatal("expected future expiry")
	}
}

func TestAccessTokenRejectsWrongSignature(t *testing.T) {
	issuer := testTokenManager(t, time.Now)
	verifier := testTokenManager(t, time.Now)
	raw, _, err := issuer.IssueAccess(UserID("11111111-1111-4111-8111-111111111111"), SessionID("22222222-2222-4222-8222-222222222222"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	_, err = verifier.VerifyAccess(raw)

	if !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("expected invalid access token, got %v", err)
	}
}

func TestAccessTokenRejectsWrongAudience(t *testing.T) {
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	issuer := NewTokenManager(privateKey, publicKey, "spendly", "spendly-ios", 15*time.Minute, time.Now)
	verifier := NewTokenManager(privateKey, publicKey, "spendly", "different-client", 15*time.Minute, time.Now)
	raw, _, err := issuer.IssueAccess(UserID("11111111-1111-4111-8111-111111111111"), SessionID("22222222-2222-4222-8222-222222222222"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}

	_, err = verifier.VerifyAccess(raw)

	if !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("expected invalid access token, got %v", err)
	}
}

func TestAccessTokenRejectsExpiredToken(t *testing.T) {
	now := time.Now()
	manager := testTokenManager(t, func() time.Time { return now })
	raw, _, err := manager.IssueAccess(UserID("11111111-1111-4111-8111-111111111111"), SessionID("22222222-2222-4222-8222-222222222222"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	manager.now = func() time.Time { return now.Add(16 * time.Minute) }

	_, err = manager.VerifyAccess(raw)

	if !errors.Is(err, ErrInvalidAccessToken) {
		t.Fatalf("expected expired token rejection, got %v", err)
	}
}

func TestRefreshTokenHas256BitsAndStableHash(t *testing.T) {
	manager := testTokenManager(t, time.Now)

	raw, hash, err := manager.NewRefreshToken()
	if err != nil {
		t.Fatalf("new refresh token: %v", err)
	}
	decoded, err := DecodeRefreshToken(raw)
	if err != nil {
		t.Fatalf("decode refresh token: %v", err)
	}
	if len(decoded) != 32 {
		t.Fatalf("expected 32 random bytes, got %d", len(decoded))
	}
	if hash != HashRefreshToken(raw) {
		t.Fatal("refresh token hash is not stable")
	}
}

func testTokenManager(t *testing.T, now func() time.Time) *TokenManager {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate key: %v", err)
	}
	return NewTokenManager(privateKey, publicKey, "spendly", "spendly-ios", 15*time.Minute, now)
}
