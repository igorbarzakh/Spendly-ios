package httpapi

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"log/slog"
	"net/http"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type AuthUseCases interface {
	SignIn(context.Context, auth.Provider, string, string) (auth.User, auth.SessionTokens, error)
	Refresh(context.Context, string) (auth.SessionTokens, error)
	Logout(context.Context, string) error
	LogoutAll(context.Context, auth.UserID) error
}

type authHandler struct {
	service AuthUseCases
	tokens  *auth.TokenManager
}

func (handler *authHandler) register(mux *http.ServeMux) {
	mux.HandleFunc("POST /v1/auth/google", handler.signIn(auth.ProviderGoogle))
	mux.HandleFunc("POST /v1/auth/apple", handler.signIn(auth.ProviderApple))
	mux.HandleFunc("POST /v1/auth/refresh", handler.refresh)
	mux.HandleFunc("POST /v1/auth/logout", handler.logout)
	mux.Handle("POST /v1/auth/logout-all", requireAccess(handler.tokens, http.HandlerFunc(handler.logoutAll)))
	mux.Handle("GET /v1/me", requireAccess(handler.tokens, http.HandlerFunc(handler.me)))
}

func (handler *authHandler) signIn(provider auth.Provider) http.HandlerFunc {
	return func(response http.ResponseWriter, request *http.Request) {
		logger := slog.Default().With(
			"request_id", response.Header().Get("X-Request-ID"),
			"provider", provider,
			"path", request.URL.Path,
		)
		var input struct {
			IDToken string `json:"id_token"`
			Nonce   string `json:"nonce"`
		}
		if err := decodeJSON(request, &input); err != nil || input.IDToken == "" || input.Nonce == "" {
			logger.Warn("auth sign-in rejected", "reason", "invalid_request")
			writeAPIError(response, 400, "invalid_request", "Invalid request")
			return
		}
		logger.Info("auth sign-in started")
		user, tokens, err := handler.service.SignIn(request.Context(), provider, input.IDToken, input.Nonce)
		if err != nil {
			logger.Error("auth sign-in failed", "error", err)
			handleAuthError(response, err)
			return
		}
		logger.Info("auth sign-in succeeded", "user_id", user.ID, "access_expires_at", tokens.AccessExpiresAt)
		writeJSON(response, 200, sessionResponse(user, tokens))
	}
}

func (handler *authHandler) refresh(response http.ResponseWriter, request *http.Request) {
	logger := slog.Default().With(
		"request_id", response.Header().Get("X-Request-ID"),
		"path", request.URL.Path,
	)
	var input struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(request, &input); err != nil || input.RefreshToken == "" {
		logger.Warn("auth refresh rejected", "reason", "invalid_request")
		writeAPIError(response, 400, "invalid_request", "Invalid request")
		return
	}
	logger.Info("auth refresh started")
	tokens, err := handler.service.Refresh(request.Context(), input.RefreshToken)
	if err != nil {
		logger.Error("auth refresh failed", "error", err)
		handleAuthError(response, err)
		return
	}
	logger.Info("auth refresh succeeded", "access_expires_at", tokens.AccessExpiresAt)
	writeJSON(response, 200, sessionResponse(auth.User{}, tokens))
}

func (handler *authHandler) logout(response http.ResponseWriter, request *http.Request) {
	logger := slog.Default().With(
		"request_id", response.Header().Get("X-Request-ID"),
		"path", request.URL.Path,
	)
	var input struct {
		RefreshToken string `json:"refresh_token"`
	}
	if err := decodeJSON(request, &input); err != nil || input.RefreshToken == "" {
		logger.Warn("auth logout rejected", "reason", "invalid_request")
		writeAPIError(response, 400, "invalid_request", "Invalid request")
		return
	}
	logger.Info("auth logout started")
	if err := handler.service.Logout(request.Context(), input.RefreshToken); err != nil {
		logger.Error("auth logout failed", "error", err)
		handleAuthError(response, err)
		return
	}
	logger.Info("auth logout succeeded")
	response.WriteHeader(http.StatusNoContent)
}

func (handler *authHandler) logoutAll(response http.ResponseWriter, request *http.Request) {
	claims, _ := accessClaims(request.Context())
	if err := handler.service.LogoutAll(request.Context(), claims.UserID); err != nil {
		handleAuthError(response, err)
		return
	}
	response.WriteHeader(204)
}
func (*authHandler) me(response http.ResponseWriter, request *http.Request) {
	claims, _ := accessClaims(request.Context())
	writeJSON(response, 200, map[string]any{"user": auth.User{ID: claims.UserID}})
}

type authSessionResponse struct {
	User             *auth.User `json:"user,omitempty"`
	AccessToken      string     `json:"access_token"`
	RefreshToken     string     `json:"refresh_token"`
	AccessExpiresAt  time.Time  `json:"access_expires_at"`
	RefreshExpiresAt time.Time  `json:"refresh_expires_at"`
}

func sessionResponse(user auth.User, tokens auth.SessionTokens) authSessionResponse {
	response := authSessionResponse{AccessToken: tokens.AccessToken, RefreshToken: tokens.RefreshToken, AccessExpiresAt: tokens.AccessExpiresAt, RefreshExpiresAt: tokens.RefreshExpiresAt}
	if user.ID != "" {
		response.User = &user
	}
	return response
}

func decodeJSON(request *http.Request, destination any) error {
	decoder := json.NewDecoder(request.Body)
	decoder.DisallowUnknownFields()
	if err := decoder.Decode(destination); err != nil {
		return err
	}
	if err := decoder.Decode(&struct{}{}); !errors.Is(err, io.EOF) {
		return errors.New("one JSON value required")
	}
	return nil
}
func handleAuthError(response http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, auth.ErrIdentityProviderUnavailable):
		writeAPIError(response, 503, "identity_provider_unavailable", "Sign-in provider is unavailable")
	case errors.Is(err, auth.ErrInvalidIdentityToken), errors.Is(err, auth.ErrInvalidRefreshToken), errors.Is(err, auth.ErrRefreshReuse):
		writeAPIError(response, 401, "unauthorized", "Authentication failed")
	default:
		writeAPIError(response, 500, "internal_error", "Internal server error")
	}
}
func writeAPIError(response http.ResponseWriter, status int, code, message string) {
	writeJSON(response, status, map[string]any{"error": map[string]string{"code": code, "message": message, "request_id": response.Header().Get("X-Request-ID")}})
}
