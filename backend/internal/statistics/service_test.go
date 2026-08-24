package statistics

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

func TestMonthlyRejectsInvalidRange(t *testing.T) {
	service := NewService(statisticsRepositoryStub{})
	now := time.Now()
	if _, err := service.Monthly(context.Background(), auth.UserID("user"), purchases.Scope{}, now, now); !errors.Is(err, ErrInvalidRange) {
		t.Fatalf("expected invalid range, got %v", err)
	}
}

type statisticsRepositoryStub struct{}

func (statisticsRepositoryStub) Monthly(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) (MonthlyResult, error) {
	return MonthlyResult{}, nil
}
