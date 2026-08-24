package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"github.com/igorbarzakh/spendly-ios/backend/internal/statistics"
)

func TestStatisticsUsesAuthenticatedUserAndScope(t *testing.T) {
	manager := httpTestTokenManager(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	raw, _, _ := manager.IssueAccess(user, auth.SessionID("22222222-2222-4222-8222-222222222222"))
	groupID := "33333333-3333-4333-8333-333333333333"
	stub := statisticsUseCasesStub{monthly: func(_ context.Context, actual auth.UserID, scope purchases.Scope, _, _ time.Time) (statistics.MonthlyResult, error) {
		if actual != user || scope.GroupID == nil || *scope.GroupID != groupID {
			t.Fatalf("unexpected user or scope: %s %+v", actual, scope)
		}
		return statistics.MonthlyResult{TotalMinor: 175}, nil
	}}
	request := httptest.NewRequest(http.MethodGet, "/v1/statistics?from=2026-08-01T00:00:00Z&to=2026-09-01T00:00:00Z&group_id="+groupID, nil)
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()
	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithStatistics(stub)).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
}

type statisticsUseCasesStub struct {
	monthly func(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) (statistics.MonthlyResult, error)
}

func (stub statisticsUseCasesStub) Monthly(ctx context.Context, user auth.UserID, scope purchases.Scope, from, to time.Time) (statistics.MonthlyResult, error) {
	return stub.monthly(ctx, user, scope, from, to)
}
