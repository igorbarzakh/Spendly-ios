package auth

import (
	"context"
	"crypto/sha256"
	"crypto/subtle"
	"encoding/hex"
	"fmt"
	"io"
	"net/http"
	"sync"
	"time"

	"github.com/lestrrat-go/jwx/v3/jwk"
	"github.com/lestrrat-go/jwx/v3/jws"
	"github.com/lestrrat-go/jwx/v3/jwt"
)

const maxJWKSBytes = 1 << 20

type OIDCConfig struct {
	Provider Provider
	Issuer   string
	Audience string
	JWKSURL  string
	CacheTTL time.Duration
}

type OIDCVerifier struct {
	config OIDCConfig
	client *http.Client
	now    func() time.Time

	mu        sync.Mutex
	keySet    jwk.Set
	expiresAt time.Time
}

func NewOIDCVerifier(config OIDCConfig, client *http.Client, now func() time.Time) *OIDCVerifier {
	if client == nil {
		client = &http.Client{Timeout: 5 * time.Second}
	}
	if now == nil {
		now = time.Now
	}
	return &OIDCVerifier{config: config, client: client, now: now}
}

func (verifier *OIDCVerifier) Verify(ctx context.Context, rawToken, rawNonce string) (Identity, error) {
	if rawToken == "" || rawNonce == "" || !verifier.validConfig() {
		return Identity{}, ErrInvalidIdentityToken
	}
	keyID, err := tokenKeyID(rawToken)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: %v", ErrInvalidIdentityToken, err)
	}
	keySet, err := verifier.keys(ctx, false)
	if err != nil {
		return Identity{}, err
	}
	if _, exists := keySet.LookupKeyID(keyID); !exists {
		keySet, err = verifier.keys(ctx, true)
		if err != nil {
			return Identity{}, err
		}
		if _, exists := keySet.LookupKeyID(keyID); !exists {
			return Identity{}, ErrInvalidIdentityToken
		}
	}

	token, err := jwt.Parse(
		[]byte(rawToken),
		jwt.WithKeySet(keySet),
		jwt.WithIssuer(verifier.config.Issuer),
		jwt.WithAudience(verifier.config.Audience),
		jwt.WithClock(jwt.ClockFunc(verifier.now)),
	)
	if err != nil {
		return Identity{}, fmt.Errorf("%w: %v", ErrInvalidIdentityToken, err)
	}
	subject, ok := token.Subject()
	if !ok || subject == "" {
		return Identity{}, ErrInvalidIdentityToken
	}
	var nonce string
	if err := token.Get("nonce", &nonce); err != nil || !secureEqual(nonce, verifier.expectedNonce(rawNonce)) {
		return Identity{}, ErrInvalidIdentityToken
	}

	identity := Identity{Provider: verifier.config.Provider, Subject: subject}
	_ = token.Get("email", &identity.Email)
	_ = token.Get("name", &identity.Name)
	return identity, nil
}

func (verifier *OIDCVerifier) validConfig() bool {
	return (verifier.config.Provider == ProviderApple || verifier.config.Provider == ProviderGoogle) &&
		verifier.config.Issuer != "" && verifier.config.Audience != "" &&
		verifier.config.JWKSURL != "" && verifier.config.CacheTTL > 0
}

func (verifier *OIDCVerifier) expectedNonce(raw string) string {
	if verifier.config.Provider != ProviderApple {
		return raw
	}
	hash := sha256.Sum256([]byte(raw))
	return hex.EncodeToString(hash[:])
}

func (verifier *OIDCVerifier) keys(ctx context.Context, force bool) (jwk.Set, error) {
	verifier.mu.Lock()
	defer verifier.mu.Unlock()
	if !force && verifier.keySet != nil && verifier.now().Before(verifier.expiresAt) {
		return verifier.keySet, nil
	}

	request, err := http.NewRequestWithContext(ctx, http.MethodGet, verifier.config.JWKSURL, nil)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrIdentityProviderUnavailable, err)
	}
	response, err := verifier.client.Do(request)
	if err != nil {
		return nil, fmt.Errorf("%w: %v", ErrIdentityProviderUnavailable, err)
	}
	defer response.Body.Close()
	if response.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("%w: JWKS returned %d", ErrIdentityProviderUnavailable, response.StatusCode)
	}
	payload, err := io.ReadAll(io.LimitReader(response.Body, maxJWKSBytes+1))
	if err != nil || len(payload) > maxJWKSBytes {
		return nil, fmt.Errorf("%w: invalid JWKS body", ErrIdentityProviderUnavailable)
	}
	set, err := jwk.Parse(payload)
	if err != nil || set.Len() == 0 {
		return nil, fmt.Errorf("%w: invalid JWKS", ErrIdentityProviderUnavailable)
	}
	verifier.keySet = set
	verifier.expiresAt = verifier.now().Add(verifier.config.CacheTTL)
	return set, nil
}

func tokenKeyID(raw string) (string, error) {
	message, err := jws.Parse([]byte(raw))
	if err != nil {
		return "", err
	}
	signatures := message.Signatures()
	if len(signatures) != 1 || signatures[0].ProtectedHeaders() == nil {
		return "", ErrInvalidIdentityToken
	}
	keyID, ok := signatures[0].ProtectedHeaders().KeyID()
	if !ok || keyID == "" {
		return "", ErrInvalidIdentityToken
	}
	return keyID, nil
}

func secureEqual(left, right string) bool {
	if len(left) != len(right) {
		return false
	}
	return subtle.ConstantTimeCompare([]byte(left), []byte(right)) == 1
}
