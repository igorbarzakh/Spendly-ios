package sync

import (
	"context"
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"encoding/json"
	"strings"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

const maxPageSize = 100

type Repository interface {
	Changes(context.Context, auth.UserID, purchases.Scope, Cursor, int) ([]Change, error)
}

type Service struct {
	repository Repository
	key        []byte
}

func NewService(repository Repository, key []byte) *Service {
	return &Service{repository: repository, key: append([]byte(nil), key...)}
}

func (service *Service) Page(ctx context.Context, user auth.UserID, scope purchases.Scope, rawCursor string, limit int) (Page, error) {
	if user == "" || len(service.key) < 32 {
		return Page{}, ErrInvalidRequest
	}
	if limit <= 0 {
		limit = maxPageSize
	}
	if limit > maxPageSize {
		limit = maxPageSize
	}

	var cursor Cursor
	var err error
	if rawCursor != "" {
		cursor, err = service.DecodeCursor(rawCursor)
		if err != nil {
			return Page{}, err
		}
	} else {
		cursor = Cursor{UpdatedAt: time.Unix(0, 0).UTC(), ID: "00000000-0000-0000-0000-000000000000"}
	}
	changes, err := service.repository.Changes(ctx, user, scope, cursor, limit)
	if err != nil {
		return Page{}, err
	}

	nextCursor := rawCursor
	if len(changes) > 0 {
		last := changes[len(changes)-1].Purchase
		nextCursor, err = service.EncodeCursor(Cursor{UpdatedAt: last.UpdatedAt, ID: last.ID})
		if err != nil {
			return Page{}, err
		}
	}
	return Page{Changes: changes, NextCursor: nextCursor}, nil
}

func (service *Service) EncodeCursor(cursor Cursor) (string, error) {
	if cursor.UpdatedAt.IsZero() || cursor.ID == "" || len(service.key) < 32 {
		return "", ErrInvalidCursor
	}
	payload, err := json.Marshal(cursor)
	if err != nil {
		return "", ErrInvalidCursor
	}
	signature := service.sign(payload)
	return base64.RawURLEncoding.EncodeToString(payload) + "." + base64.RawURLEncoding.EncodeToString(signature), nil
}

func (service *Service) DecodeCursor(raw string) (Cursor, error) {
	parts := strings.Split(raw, ".")
	if len(parts) != 2 || len(service.key) < 32 {
		return Cursor{}, ErrInvalidCursor
	}
	payload, err := base64.RawURLEncoding.DecodeString(parts[0])
	if err != nil {
		return Cursor{}, ErrInvalidCursor
	}
	signature, err := base64.RawURLEncoding.DecodeString(parts[1])
	if err != nil || !hmac.Equal(signature, service.sign(payload)) {
		return Cursor{}, ErrInvalidCursor
	}
	var cursor Cursor
	if json.Unmarshal(payload, &cursor) != nil || cursor.UpdatedAt.IsZero() || cursor.ID == "" {
		return Cursor{}, ErrInvalidCursor
	}
	return cursor, nil
}

func (service *Service) sign(payload []byte) []byte {
	mac := hmac.New(sha256.New, service.key)
	_, _ = mac.Write(payload)
	return mac.Sum(nil)
}
