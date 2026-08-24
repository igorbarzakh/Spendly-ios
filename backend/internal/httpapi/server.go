package httpapi

import (
	"context"
	"crypto/rand"
	"encoding/hex"
	"encoding/json"
	"net/http"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

const maxRequestBodyBytes = 1 << 20
const readinessTimeout = 2 * time.Second

type ReadinessProbe interface {
	Ping(context.Context) error
}

type handlerConfig struct {
	authService AuthUseCases
	tokens      *auth.TokenManager
	purchases   PurchaseUseCases
	groups      GroupUseCases
}

func WithPurchases(service PurchaseUseCases) HandlerOption {
	return func(config *handlerConfig) { config.purchases = service }
}
func WithGroups(service GroupUseCases) HandlerOption {
	return func(config *handlerConfig) { config.groups = service }
}

type HandlerOption func(*handlerConfig)

func WithAuth(service AuthUseCases, tokens *auth.TokenManager) HandlerOption {
	return func(config *handlerConfig) { config.authService = service; config.tokens = tokens }
}

func NewHandler(probe ReadinessProbe, options ...HandlerOption) http.Handler {
	var config handlerConfig
	for _, option := range options {
		option(&config)
	}
	mux := http.NewServeMux()
	mux.HandleFunc("GET /health/live", func(response http.ResponseWriter, _ *http.Request) {
		writeJSON(response, http.StatusOK, map[string]string{"status": "ok"})
	})
	mux.HandleFunc("GET /health/ready", func(response http.ResponseWriter, request *http.Request) {
		if probe == nil {
			writeJSON(response, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		ctx, cancel := context.WithTimeout(request.Context(), readinessTimeout)
		defer cancel()
		if probe.Ping(ctx) != nil {
			writeJSON(response, http.StatusServiceUnavailable, map[string]string{"status": "unavailable"})
			return
		}
		writeJSON(response, http.StatusOK, map[string]string{"status": "ok"})
	})
	if config.authService != nil && config.tokens != nil {
		(&authHandler{service: config.authService, tokens: config.tokens}).register(mux)
	}
	if config.purchases != nil && config.tokens != nil {
		(&purchasesHandler{service: config.purchases}).register(mux, config.tokens)
	}
	if config.groups != nil && config.tokens != nil {
		(&groupsHandler{service: config.groups}).register(mux, config.tokens)
	}

	return requestID(http.MaxBytesHandler(mux, maxRequestBodyBytes))
}

func requestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		id := request.Header.Get("X-Request-ID")
		if id == "" {
			id = newRequestID()
		}
		response.Header().Set("X-Request-ID", id)
		next.ServeHTTP(response, request)
	})
}

func newRequestID() string {
	var bytes [16]byte
	if _, err := rand.Read(bytes[:]); err != nil {
		return "unavailable"
	}
	return hex.EncodeToString(bytes[:])
}

func writeJSON(response http.ResponseWriter, status int, value any) {
	response.Header().Set("Content-Type", "application/json")
	response.WriteHeader(status)
	_ = json.NewEncoder(response).Encode(value)
}
