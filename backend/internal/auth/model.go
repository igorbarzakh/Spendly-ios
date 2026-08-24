package auth

import (
	"errors"
	"time"
)

type UserID string
type SessionID string

var (
	ErrInvalidAccessToken  = errors.New("invalid access token")
	ErrInvalidRefreshToken = errors.New("invalid refresh token")
	ErrRefreshReuse        = errors.New("refresh token reuse detected")
)

type AccessClaims struct {
	UserID    UserID
	SessionID SessionID
}

type SessionTokens struct {
	AccessToken      string
	RefreshToken     string
	AccessExpiresAt  time.Time
	RefreshExpiresAt time.Time
}

type SessionRecord struct {
	ID        SessionID
	FamilyID  string
	UserID    UserID
	TokenHash [32]byte
	ExpiresAt time.Time
	CreatedAt time.Time
}
