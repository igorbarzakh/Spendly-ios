package auth

import (
	"crypto/ed25519"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"time"

	"github.com/lestrrat-go/jwx/v3/jwa"
	"github.com/lestrrat-go/jwx/v3/jwt"
)

type TokenManager struct {
	privateKey ed25519.PrivateKey
	publicKey  ed25519.PublicKey
	issuer     string
	audience   string
	accessTTL  time.Duration
	now        func() time.Time
}

func NewTokenManager(
	privateKey ed25519.PrivateKey,
	publicKey ed25519.PublicKey,
	issuer string,
	audience string,
	accessTTL time.Duration,
	now func() time.Time,
) *TokenManager {
	return &TokenManager{
		privateKey: privateKey,
		publicKey:  publicKey,
		issuer:     issuer,
		audience:   audience,
		accessTTL:  accessTTL,
		now:        now,
	}
}

func (manager *TokenManager) IssueAccess(userID UserID, sessionID SessionID) (string, time.Time, error) {
	if len(manager.privateKey) != ed25519.PrivateKeySize || userID == "" || sessionID == "" || manager.accessTTL <= 0 {
		return "", time.Time{}, ErrInvalidAccessToken
	}
	now := manager.now().UTC()
	expiresAt := now.Add(manager.accessTTL)
	token, err := jwt.NewBuilder().
		Issuer(manager.issuer).
		Audience([]string{manager.audience}).
		Subject(string(userID)).
		JwtID(string(sessionID)).
		IssuedAt(now).
		NotBefore(now).
		Expiration(expiresAt).
		Build()
	if err != nil {
		return "", time.Time{}, fmt.Errorf("build access token: %w", err)
	}
	signed, err := jwt.Sign(token, jwt.WithKey(jwa.EdDSAEd25519(), manager.privateKey))
	if err != nil {
		return "", time.Time{}, fmt.Errorf("sign access token: %w", err)
	}
	return string(signed), expiresAt, nil
}

func (manager *TokenManager) VerifyAccess(raw string) (AccessClaims, error) {
	if len(manager.publicKey) != ed25519.PublicKeySize || raw == "" {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	token, err := jwt.Parse(
		[]byte(raw),
		jwt.WithKey(jwa.EdDSAEd25519(), manager.publicKey),
		jwt.WithIssuer(manager.issuer),
		jwt.WithAudience(manager.audience),
		jwt.WithClock(jwt.ClockFunc(manager.now)),
	)
	if err != nil {
		return AccessClaims{}, fmt.Errorf("%w: %v", ErrInvalidAccessToken, err)
	}
	userID, ok := token.Subject()
	if !ok || userID == "" {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	sessionID, ok := token.JwtID()
	if !ok || sessionID == "" {
		return AccessClaims{}, ErrInvalidAccessToken
	}
	return AccessClaims{UserID: UserID(userID), SessionID: SessionID(sessionID)}, nil
}

func (manager *TokenManager) NewRefreshToken() (string, [32]byte, error) {
	var randomBytes [32]byte
	if _, err := rand.Read(randomBytes[:]); err != nil {
		return "", [32]byte{}, err
	}
	raw := base64.RawURLEncoding.EncodeToString(randomBytes[:])
	return raw, HashRefreshToken(raw), nil
}

func DecodeRefreshToken(raw string) ([]byte, error) {
	decoded, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil || len(decoded) != 32 {
		return nil, ErrInvalidRefreshToken
	}
	return decoded, nil
}

func HashRefreshToken(raw string) [32]byte {
	return sha256.Sum256([]byte(raw))
}

func ParseSigningKey(encoded string) (ed25519.PrivateKey, ed25519.PublicKey, error) {
	raw, err := base64.RawStdEncoding.DecodeString(encoded)
	if err != nil {
		return nil, nil, err
	}
	var seed []byte
	switch len(raw) {
	case ed25519.SeedSize:
		seed = raw
	case ed25519.PrivateKeySize:
		seed = raw[:ed25519.SeedSize]
	default:
		return nil, nil, errors.New("Ed25519 signing key must be a 32-byte seed or 64-byte private key")
	}
	privateKey := ed25519.NewKeyFromSeed(seed)
	publicKey, ok := privateKey.Public().(ed25519.PublicKey)
	if !ok {
		return nil, nil, errors.New("derive Ed25519 public key")
	}
	return privateKey, publicKey, nil
}
