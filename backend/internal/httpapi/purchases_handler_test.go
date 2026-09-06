package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

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

func TestListPurchasesPassesCursorAndLimitWithoutDateRange(t *testing.T) {
	manager := httpTestTokenManager(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	raw, _, _ := manager.IssueAccess(user, auth.SessionID("22222222-2222-4222-8222-222222222222"))
	stub := &purchaseUseCasesStub{list: func(_ context.Context, actual auth.UserID, _ purchases.Scope, options purchases.ListOptions) (purchases.Page, error) {
		if actual != user || options.Cursor != "cursor-value" || options.Limit != 25 {
			t.Fatalf("unexpected list input: %s %+v", actual, options)
		}
		if !options.From.IsZero() || !options.To.IsZero() {
			t.Fatalf("expected optional date range, got %+v", options)
		}
		return purchases.Page{Purchases: []purchases.Purchase{}, NextCursor: "next", HasMore: true}, nil
	}}
	request := httptest.NewRequest(http.MethodGet, "/v1/purchases?cursor=cursor-value&limit=25", nil)
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()

	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithPurchases(stub)).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	if !strings.Contains(response.Body.String(), `"next_cursor":"next"`) || !strings.Contains(response.Body.String(), `"has_more":true`) {
		t.Fatalf("unexpected response: %s", response.Body.String())
	}
}

func TestListPurchasesRejectsInvalidCursor(t *testing.T) {
	manager := httpTestTokenManager(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	raw, _, _ := manager.IssueAccess(user, auth.SessionID("22222222-2222-4222-8222-222222222222"))
	stub := &purchaseUseCasesStub{list: func(context.Context, auth.UserID, purchases.Scope, purchases.ListOptions) (purchases.Page, error) {
		return purchases.Page{}, purchases.ErrInvalidCursor
	}}
	request := httptest.NewRequest(http.MethodGet, "/v1/purchases?cursor=invalid", nil)
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()

	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithPurchases(stub)).ServeHTTP(response, request)

	if response.Code != http.StatusBadRequest || !strings.Contains(response.Body.String(), `"code":"invalid_cursor"`) {
		t.Fatalf("unexpected response: %d %s", response.Code, response.Body.String())
	}
}

type purchaseUseCasesStub struct {
	create func(context.Context, auth.UserID, purchases.Draft, string) (purchases.Purchase, error)
	list   func(context.Context, auth.UserID, purchases.Scope, purchases.ListOptions) (purchases.Page, error)
}

func (s *purchaseUseCasesStub) Create(c context.Context, u auth.UserID, d purchases.Draft, k string) (purchases.Purchase, error) {
	return s.create(c, u, d, k)
}
func (s *purchaseUseCasesStub) List(ctx context.Context, user auth.UserID, scope purchases.Scope, options purchases.ListOptions) (purchases.Page, error) {
	if s.list == nil {
		return purchases.Page{}, nil
	}
	return s.list(ctx, user, scope, options)
}
func (*purchaseUseCasesStub) Update(context.Context, auth.UserID, purchases.Purchase, int64) (purchases.Purchase, error) {
	return purchases.Purchase{}, nil
}
func (*purchaseUseCasesStub) Delete(context.Context, auth.UserID, string, int64) error { return nil }
