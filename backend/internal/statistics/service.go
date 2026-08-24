package statistics

import (
	"context"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

type Repository interface {
	Monthly(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) (MonthlyResult, error)
}

type Service struct {
	repository Repository
}

func NewService(repository Repository) *Service {
	return &Service{repository: repository}
}

func (service *Service) Monthly(ctx context.Context, user auth.UserID, scope purchases.Scope, from, to time.Time) (MonthlyResult, error) {
	if user == "" || from.IsZero() || !to.After(from) {
		return MonthlyResult{}, ErrInvalidRange
	}
	return service.repository.Monthly(ctx, user, scope, from, to)
}
