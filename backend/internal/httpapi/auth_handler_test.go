package httpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

func TestGoogleSignInReturnsSpendlySession(t *testing.T) {
	logs := captureTestLogs(t)
	service := &authServiceStub{
		signIn: func(_ context.Context, provider auth.Provider, idToken, nonce string) (auth.User, auth.SessionTokens, error) {
			if provider != auth.ProviderGoogle || idToken != "provider-token" || nonce != "nonce" {
				t.Fatalf("unexpected sign-in input: %s %s %s", provider, idToken, nonce)
			}
			return auth.User{ID: auth.UserID("11111111-1111-4111-8111-111111111111")}, auth.SessionTokens{
				AccessToken: "access", RefreshToken: "refresh",
				AccessExpiresAt: time.Unix(2_000_000_000, 0), RefreshExpiresAt: time.Unix(2_100_000_000, 0),
			}, nil
		},
	}
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/google", strings.NewReader(`{"id_token":"provider-token","nonce":"nonce"}`))
	request.Header.Set("Content-Type", "application/json")
	response := httptest.NewRecorder()

	NewHandler(nil, WithAuth(service, httpTestTokenManager(t))).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", response.Code, response.Body.String())
	}
	var payload struct {
		User struct {
			ID string `json:"id"`
		} `json:"user"`
		AccessToken  string `json:"access_token"`
		RefreshToken string `json:"refresh_token"`
	}
	if err := json.NewDecoder(response.Body).Decode(&payload); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if payload.User.ID == "" || payload.AccessToken != "access" || payload.RefreshToken != "refresh" {
		t.Fatalf("unexpected response: %+v", payload)
	}
	if !strings.Contains(logs.String(), `"msg":"auth sign-in succeeded"`) {
		t.Fatalf("expected success auth log, got %s", logs.String())
	}
}

func TestSignInMapsInvalidProviderTokenToUniformUnauthorized(t *testing.T) {
	logs := captureTestLogs(t)
	service := &authServiceStub{signIn: func(context.Context, auth.Provider, string, string) (auth.User, auth.SessionTokens, error) {
		return auth.User{}, auth.SessionTokens{}, auth.ErrInvalidIdentityToken
	}}
	request := httptest.NewRequest(http.MethodPost, "/v1/auth/apple", strings.NewReader(`{"id_token":"invalid","nonce":"nonce"}`))
	response := httptest.NewRecorder()

	NewHandler(nil, WithAuth(service, httpTestTokenManager(t))).ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
	if strings.Contains(response.Body.String(), "identity token") {
		t.Fatalf("internal authentication detail leaked: %s", response.Body.String())
	}
	if !strings.Contains(logs.String(), `"msg":"auth sign-in failed"`) {
		t.Fatalf("expected failed auth log, got %s", logs.String())
	}
}

func TestMeRequiresAccessToken(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/v1/me", nil)
	response := httptest.NewRecorder()

	NewHandler(nil, WithAuth(&authServiceStub{}, httpTestTokenManager(t))).ServeHTTP(response, request)

	if response.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", response.Code)
	}
}

type authServiceStub struct {
	signIn func(context.Context, auth.Provider, string, string) (auth.User, auth.SessionTokens, error)
}

func (service *authServiceStub) SignIn(ctx context.Context, provider auth.Provider, idToken, nonce string) (auth.User, auth.SessionTokens, error) {
	if service.signIn == nil {
		return auth.User{}, auth.SessionTokens{}, errors.New("unexpected sign in")
	}
	return service.signIn(ctx, provider, idToken, nonce)
}

func (*authServiceStub) Refresh(context.Context, string) (auth.SessionTokens, error) {
	return auth.SessionTokens{}, errors.New("unexpected refresh")
}

func (*authServiceStub) Logout(context.Context, string) error {
	return errors.New("unexpected logout")
}

func (*authServiceStub) LogoutAll(context.Context, auth.UserID) error {
	return errors.New("unexpected logout all")
}

func captureTestLogs(t *testing.T) *bytes.Buffer {
	t.Helper()

	var buffer bytes.Buffer
	previous := slog.Default()
	slog.SetDefault(slog.New(slog.NewJSONHandler(&buffer, nil)))
	t.Cleanup(func() {
		slog.SetDefault(previous)
	})
	return &buffer
}
