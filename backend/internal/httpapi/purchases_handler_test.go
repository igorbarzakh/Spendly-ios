package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

func TestCreatePurchaseUsesAccessTokenOwner(t *testing.T) {
	manager := httpTestTokenManager(t)
	raw, _, _ := manager.IssueAccess(auth.UserID("11111111-1111-4111-8111-111111111111"), auth.SessionID("22222222-2222-4222-8222-222222222222"))
	stub := &purchaseUseCasesStub{create: func(_ context.Context, user auth.UserID, _ purchases.Draft, key string) (purchases.Purchase, error) {
		if user != "11111111-1111-4111-8111-111111111111" || key != "44444444-4444-4444-8444-444444444444" {
			t.Fatalf("unexpected owner/key %s %s", user, key)
		}
		return purchases.Purchase{OwnerID: user, Version: 1}, nil
	}}
	body := `{"id":"22222222-2222-4222-8222-222222222222","kind":"quick","merchant":"Market","category":"Food","amount_minor":100,"currency_code":"RUB","spent_at":"2026-08-24T12:00:00Z","local_date":"2026-08-24","time_zone":"Europe/Moscow"}`
	request := httptest.NewRequest(http.MethodPost, "/v1/purchases", strings.NewReader(body))
	request.Header.Set("Authorization", "Bearer "+raw)
	request.Header.Set("Idempotency-Key", "44444444-4444-4444-8444-444444444444")
	response := httptest.NewRecorder()
	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithPurchases(stub)).ServeHTTP(response, request)
	if response.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
}

type purchaseUseCasesStub struct {
	create func(context.Context, auth.UserID, purchases.Draft, string) (purchases.Purchase, error)
}

func (s *purchaseUseCasesStub) Create(c context.Context, u auth.UserID, d purchases.Draft, k string) (purchases.Purchase, error) {
	return s.create(c, u, d, k)
}
func (*purchaseUseCasesStub) List(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) ([]purchases.Purchase, error) {
	return nil, nil
}
func (*purchaseUseCasesStub) Update(context.Context, auth.UserID, purchases.Purchase, int64) (purchases.Purchase, error) {
	return purchases.Purchase{}, nil
}
func (*purchaseUseCasesStub) Delete(context.Context, auth.UserID, string, int64) error { return nil }
