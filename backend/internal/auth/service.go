package auth

import (
	"context"
	"crypto/rand"
	"fmt"
	"time"
)

type SessionService struct {
	repository *SessionRepository
	tokens     *TokenManager
	refreshTTL time.Duration
	now        func() time.Time
}

func NewSessionService(repository *SessionRepository, tokens *TokenManager, refreshTTL time.Duration, now func() time.Time) *SessionService {
	return &SessionService{repository: repository, tokens: tokens, refreshTTL: refreshTTL, now: now}
}

func (service *SessionService) Issue(ctx context.Context, userID UserID) (SessionTokens, error) {
	now := service.now().UTC()
	sessionID, err := newUUID()
	if err != nil {
		return SessionTokens{}, err
	}
	familyID, err := newUUID()
	if err != nil {
		return SessionTokens{}, err
	}
	rawRefresh, refreshHash, err := service.tokens.NewRefreshToken()
	if err != nil {
		return SessionTokens{}, err
	}
	refreshExpiresAt := now.Add(service.refreshTTL)
	accessToken, accessExpiresAt, err := service.tokens.IssueAccess(userID, SessionID(sessionID))
	if err != nil {
		return SessionTokens{}, err
	}
	if err := service.repository.Create(ctx, SessionRecord{
		ID: SessionID(sessionID), FamilyID: familyID, UserID: userID,
		TokenHash: refreshHash, ExpiresAt: refreshExpiresAt, CreatedAt: now,
	}); err != nil {
		return SessionTokens{}, err
	}
	return SessionTokens{
		AccessToken: accessToken, RefreshToken: rawRefresh,
		AccessExpiresAt: accessExpiresAt, RefreshExpiresAt: refreshExpiresAt,
	}, nil
}

func (service *SessionService) Refresh(ctx context.Context, currentRaw string) (SessionTokens, error) {
	if _, err := DecodeRefreshToken(currentRaw); err != nil {
		return SessionTokens{}, err
	}
	now := service.now().UTC()
	nextID, err := newUUID()
	if err != nil {
		return SessionTokens{}, err
	}
	nextRaw, nextHash, err := service.tokens.NewRefreshToken()
	if err != nil {
		return SessionTokens{}, err
	}
	refreshExpiresAt := now.Add(service.refreshTTL)
	userID, err := service.repository.Rotate(ctx, HashRefreshToken(currentRaw), SessionRecord{
		ID: SessionID(nextID), TokenHash: nextHash, ExpiresAt: refreshExpiresAt, CreatedAt: now,
	}, now)
	if err != nil {
		return SessionTokens{}, err
	}
	accessToken, accessExpiresAt, err := service.tokens.IssueAccess(userID, SessionID(nextID))
	if err != nil {
		return SessionTokens{}, err
	}
	return SessionTokens{
		AccessToken: accessToken, RefreshToken: nextRaw,
		AccessExpiresAt: accessExpiresAt, RefreshExpiresAt: refreshExpiresAt,
	}, nil
}

func (service *SessionService) Logout(ctx context.Context, raw string) error {
	if _, err := DecodeRefreshToken(raw); err != nil {
		return err
	}
	return service.repository.Revoke(ctx, HashRefreshToken(raw), service.now().UTC())
}

func (service *SessionService) LogoutAll(ctx context.Context, userID UserID) error {
	return service.repository.RevokeAll(ctx, userID, service.now().UTC())
}

func newUUID() (string, error) {
	var value [16]byte
	if _, err := rand.Read(value[:]); err != nil {
		return "", err
	}
	value[6] = (value[6] & 0x0f) | 0x40
	value[8] = (value[8] & 0x3f) | 0x80
	return fmt.Sprintf("%08x-%04x-%04x-%04x-%012x", value[0:4], value[4:6], value[6:8], value[8:10], value[10:16]), nil
}
