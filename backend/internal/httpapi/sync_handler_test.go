package httpapi

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	syncapi "github.com/igorbarzakh/spendly-ios/backend/internal/sync"
)

func TestSyncPassesCursorAndBoundedLimit(t *testing.T) {
	manager := httpTestTokenManager(t)
	user := auth.UserID("11111111-1111-4111-8111-111111111111")
	raw, _, _ := manager.IssueAccess(user, auth.SessionID("22222222-2222-4222-8222-222222222222"))
	stub := syncUseCasesStub{page: func(_ context.Context, actual auth.UserID, _ purchases.Scope, cursor string, limit int) (syncapi.Page, error) {
		if actual != user || cursor != "cursor-value" || limit != 25 {
			t.Fatalf("unexpected sync input: %s %q %d", actual, cursor, limit)
		}
		return syncapi.Page{NextCursor: "next"}, nil
	}}
	request := httptest.NewRequest(http.MethodGet, "/v1/sync?cursor=cursor-value&limit=25", nil)
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()
	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithSync(stub)).ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
}

type syncUseCasesStub struct {
	page func(context.Context, auth.UserID, purchases.Scope, string, int) (syncapi.Page, error)
}

func (stub syncUseCasesStub) Page(ctx context.Context, user auth.UserID, scope purchases.Scope, cursor string, limit int) (syncapi.Page, error) {
	return stub.page(ctx, user, scope, cursor, limit)
}
