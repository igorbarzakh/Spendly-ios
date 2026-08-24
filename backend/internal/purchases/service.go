package purchases

import (
	"context"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type Repository interface {
	Create(context.Context, auth.UserID, Draft, string) (Purchase, error)
	List(context.Context, auth.UserID, Scope, time.Time, time.Time) ([]Purchase, error)
	Update(context.Context, auth.UserID, Purchase, int64) (Purchase, error)
	Delete(context.Context, auth.UserID, string, int64) error
}

type Service struct{ repository Repository }

func NewService(repository Repository) *Service { return &Service{repository: repository} }

func (service *Service) Create(ctx context.Context, owner auth.UserID, draft Draft, idempotencyKey string) (Purchase, error) {
	if owner == "" || idempotencyKey == "" || draft.validate() != nil {
		return Purchase{}, ErrInvalidPurchase
	}
	return service.repository.Create(ctx, owner, draft, idempotencyKey)
}
func (service *Service) List(ctx context.Context, user auth.UserID, scope Scope, from, to time.Time) ([]Purchase, error) {
	if user == "" || from.IsZero() || !to.After(from) {
		return nil, ErrInvalidPurchase
	}
	return service.repository.List(ctx, user, scope, from, to)
}
func (service *Service) Update(ctx context.Context, user auth.UserID, purchase Purchase, expected int64) (Purchase, error) {
	if user == "" || expected <= 0 || purchase.Draft.validate() != nil {
		return Purchase{}, ErrInvalidPurchase
	}
	return service.repository.Update(ctx, user, purchase, expected)
}
func (service *Service) Delete(ctx context.Context, user auth.UserID, id string, expected int64) error {
	if user == "" || id == "" || expected <= 0 {
		return ErrInvalidPurchase
	}
	return service.repository.Delete(ctx, user, id, expected)
}
