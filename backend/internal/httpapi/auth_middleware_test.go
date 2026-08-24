package httpapi

import (
	"crypto/ed25519"
	"crypto/rand"
	"net/http"
	"net/http/httptest"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

func TestRequireAccessRejectsMissingBearerToken(t *testing.T) {
	manager := httpTestTokenManager(t)
	request := httptest.NewRequest(http.MethodGet, "/private", nil)
	response := httptest.NewRecorder()

	requireAccess(manager, http.HandlerFunc(func(http.ResponseWriter, *http.Request) {
		t.Fatal("protected handler must not run")
	})).ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}

func TestRequireAccessAddsClaimsToContext(t *testing.T) {
	manager := httpTestTokenManager(t)
	raw, _, err := manager.IssueAccess(auth.UserID("11111111-1111-4111-8111-111111111111"), auth.SessionID("22222222-2222-4222-8222-222222222222"))
	if err != nil {
		t.Fatalf("issue access token: %v", err)
	}
	request := httptest.NewRequest(http.MethodGet, "/private", nil)
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()

	requireAccess(manager, http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		claims, ok := accessClaims(request.Context())
		if !ok || claims.UserID != auth.UserID("11111111-1111-4111-8111-111111111111") {
			t.Fatalf("unexpected claims: %+v", claims)
		}
		response.WriteHeader(http.StatusNoContent)
	})).ServeHTTP(response, request)

	if response.Code != http.StatusNoContent {
		t.Fatalf("expected 204, got %d", response.Code)
	}
}

func httpTestTokenManager(t *testing.T) *auth.TokenManager {
	t.Helper()
	publicKey, privateKey, err := ed25519.GenerateKey(rand.Reader)
	if err != nil {
		t.Fatalf("generate signing key: %v", err)
	}
	return auth.NewTokenManager(privateKey, publicKey, "spendly", "spendly-ios", 15*time.Minute, time.Now)
}
