package auth

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"net/http"
	"net/http/httptest"
	"sync"
	"testing"
	"time"

	"github.com/lestrrat-go/jwx/v3/jwa"
	"github.com/lestrrat-go/jwx/v3/jwk"
	"github.com/lestrrat-go/jwx/v3/jwt"
)

func TestOIDCVerifierAcceptsGoogleIdentity(t *testing.T) {
	now := time.Now().UTC()
	fixture := newOIDCFixture(t, "google-key")
	server := newJWKSServer(t, fixture.publicSet)
	verifier := NewOIDCVerifier(OIDCConfig{
		Provider: ProviderGoogle, Issuer: "https://accounts.google.com", Audience: "google-client",
		JWKSURL: server.URL, CacheTTL: time.Hour,
	}, server.Client(), func() time.Time { return now })
	raw := fixture.sign(t, map[string]any{
		"iss": "https://accounts.google.com", "aud": []string{"google-client"},
		"sub": "google-subject", "email": "person@example.com", "name": "Person",
		"nonce": "nonce-123", "iat": now, "exp": now.Add(time.Hour),
	})

	identity, err := verifier.Verify(context.Background(), raw, "nonce-123")

	if err != nil {
		t.Fatalf("verify identity: %v", err)
	}
	if identity.Provider != ProviderGoogle || identity.Subject != "google-subject" {
		t.Fatalf("unexpected identity: %+v", identity)
	}
	if identity.Email != "person@example.com" || identity.Name != "Person" {
		t.Fatalf("unexpected profile hints: %+v", identity)
	}
}

func TestOIDCVerifierHashesAppleNonce(t *testing.T) {
	now := time.Now().UTC()
	fixture := newOIDCFixture(t, "apple-key")
	server := newJWKSServer(t, fixture.publicSet)
	verifier := NewOIDCVerifier(OIDCConfig{
		Provider: ProviderApple, Issuer: "https://appleid.apple.com", Audience: "app.spendly.ios",
		JWKSURL: server.URL, CacheTTL: time.Hour,
	}, server.Client(), func() time.Time { return now })
	nonceHash := sha256.Sum256([]byte("raw-nonce"))
	raw := fixture.sign(t, map[string]any{
		"iss": "https://appleid.apple.com", "aud": []string{"app.spendly.ios"},
		"sub": "apple-subject", "nonce": hex.EncodeToString(nonceHash[:]),
		"iat": now, "exp": now.Add(time.Hour),
	})

	identity, err := verifier.Verify(context.Background(), raw, "raw-nonce")

	if err != nil {
		t.Fatalf("verify Apple identity: %v", err)
	}
	if identity.Subject != "apple-subject" {
		t.Fatalf("unexpected subject %q", identity.Subject)
	}
}

func TestOIDCVerifierRejectsInvalidClaims(t *testing.T) {
	now := time.Now().UTC()
	fixture := newOIDCFixture(t, "provider-key")
	server := newJWKSServer(t, fixture.publicSet)
	verifier := NewOIDCVerifier(OIDCConfig{
		Provider: ProviderGoogle, Issuer: "issuer", Audience: "audience",
		JWKSURL: server.URL, CacheTTL: time.Hour,
	}, server.Client(), func() time.Time { return now })

	tests := []struct {
		name   string
		claims map[string]any
		nonce  string
	}{
		{name: "issuer", claims: validOIDCClaims(now, "wrong", "audience", "subject", "nonce"), nonce: "nonce"},
		{name: "audience", claims: validOIDCClaims(now, "issuer", "wrong", "subject", "nonce"), nonce: "nonce"},
		{name: "expired", claims: validOIDCClaims(now.Add(-2*time.Hour), "issuer", "audience", "subject", "nonce"), nonce: "nonce"},
		{name: "nonce", claims: validOIDCClaims(now, "issuer", "audience", "subject", "different"), nonce: "nonce"},
		{name: "missing subject", claims: validOIDCClaims(now, "issuer", "audience", "", "nonce"), nonce: "nonce"},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			raw := fixture.sign(t, tt.claims)
			_, err := verifier.Verify(context.Background(), raw, tt.nonce)
			if !errors.Is(err, ErrInvalidIdentityToken) {
				t.Fatalf("expected invalid identity token, got %v", err)
			}
		})
	}
}

func TestOIDCVerifierRefreshesJWKSForUnknownKeyID(t *testing.T) {
	now := time.Now().UTC()
	first := newOIDCFixture(t, "first-key")
	second := newOIDCFixture(t, "second-key")
	server := newJWKSServer(t, first.publicSet)
	verifier := NewOIDCVerifier(OIDCConfig{
		Provider: ProviderGoogle, Issuer: "issuer", Audience: "audience",
		JWKSURL: server.URL, CacheTTL: time.Hour,
	}, server.Client(), func() time.Time { return now })

	if _, err := verifier.Verify(context.Background(), first.sign(t, validOIDCClaims(now, "issuer", "audience", "first", "nonce")), "nonce"); err != nil {
		t.Fatalf("prime cache: %v", err)
	}
	server.set(second.publicSet)
	identity, err := verifier.Verify(context.Background(), second.sign(t, validOIDCClaims(now, "issuer", "audience", "second", "nonce")), "nonce")
	if err != nil {
		t.Fatalf("verify rotated key: %v", err)
	}
	if identity.Subject != "second" {
		t.Fatalf("unexpected identity %+v", identity)
	}
	if server.requests() != 2 {
		t.Fatalf("expected one initial fetch and one refresh, got %d", server.requests())
	}
}

func TestOIDCVerifierCachesJWKSUntilTTL(t *testing.T) {
	now := time.Now().UTC()
	currentNow := now
	fixture := newOIDCFixture(t, "cached-key")
	server := newJWKSServer(t, fixture.publicSet)
	verifier := NewOIDCVerifier(OIDCConfig{
		Provider: ProviderGoogle, Issuer: "issuer", Audience: "audience",
		JWKSURL: server.URL, CacheTTL: 5 * time.Minute,
	}, server.Client(), func() time.Time { return currentNow })
	raw := fixture.sign(t, validOIDCClaims(now, "issuer", "audience", "subject", "nonce"))

	if _, err := verifier.Verify(context.Background(), raw, "nonce"); err != nil {
		t.Fatalf("first verify: %v", err)
	}
	if _, err := verifier.Verify(context.Background(), raw, "nonce"); err != nil {
		t.Fatalf("cached verify: %v", err)
	}
	if server.requests() != 1 {
		t.Fatalf("expected one JWKS request, got %d", server.requests())
	}
	currentNow = now.Add(10 * time.Minute)
	if _, err := verifier.Verify(context.Background(), raw, "nonce"); err != nil {
		t.Fatalf("verify after cache expiry: %v", err)
	}
	if server.requests() != 2 {
		t.Fatalf("expected JWKS refresh after TTL, got %d requests", server.requests())
	}
}

type oidcFixture struct {
	privateKey jwk.Key
	publicSet  jwk.Set
}

func newOIDCFixture(t *testing.T, keyID string) oidcFixture {
	t.Helper()
	raw, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		t.Fatalf("generate RSA key: %v", err)
	}
	privateKey, err := jwk.Import(raw)
	if err != nil {
		t.Fatalf("import private key: %v", err)
	}
	if err := privateKey.Set(jwk.KeyIDKey, keyID); err != nil {
		t.Fatalf("set key ID: %v", err)
	}
	if err := privateKey.Set(jwk.AlgorithmKey, jwa.RS256()); err != nil {
		t.Fatalf("set algorithm: %v", err)
	}
	publicKey, err := jwk.PublicKeyOf(privateKey)
	if err != nil {
		t.Fatalf("derive public key: %v", err)
	}
	set := jwk.NewSet()
	if err := set.AddKey(publicKey); err != nil {
		t.Fatalf("add public key: %v", err)
	}
	return oidcFixture{privateKey: privateKey, publicSet: set}
}

func (fixture oidcFixture) sign(t *testing.T, claims map[string]any) string {
	t.Helper()
	builder := jwt.NewBuilder()
	for name, value := range claims {
		builder.Claim(name, value)
	}
	token, err := builder.Build()
	if err != nil {
		t.Fatalf("build token: %v", err)
	}
	signed, err := jwt.Sign(token, jwt.WithKey(jwa.RS256(), fixture.privateKey))
	if err != nil {
		t.Fatalf("sign token: %v", err)
	}
	return string(signed)
}

func validOIDCClaims(now time.Time, issuer, audience, subject, nonce string) map[string]any {
	return map[string]any{
		"iss": issuer, "aud": []string{audience}, "sub": subject, "nonce": nonce,
		"iat": now, "exp": now.Add(time.Hour),
	}
}

type jwksServer struct {
	*httptest.Server
	mu      sync.Mutex
	current jwk.Set
	request int
}

func newJWKSServer(t *testing.T, set jwk.Set) *jwksServer {
	t.Helper()
	server := &jwksServer{current: set}
	server.Server = httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		server.mu.Lock()
		defer server.mu.Unlock()
		server.request++
		response.Header().Set("Content-Type", "application/json")
		if err := json.NewEncoder(response).Encode(server.current); err != nil {
			t.Errorf("encode JWKS: %v", err)
		}
	}))
	t.Cleanup(server.Close)
	return server
}

func (server *jwksServer) set(value jwk.Set) {
	server.mu.Lock()
	defer server.mu.Unlock()
	server.current = value
}

func (server *jwksServer) requests() int {
	server.mu.Lock()
	defer server.mu.Unlock()
	return server.request
}
