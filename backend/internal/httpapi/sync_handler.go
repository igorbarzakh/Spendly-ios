package httpapi

import (
	"context"
	"errors"
	"net/http"
	"strconv"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	syncapi "github.com/igorbarzakh/spendly-ios/backend/internal/sync"
)

type SyncUseCases interface {
	Page(context.Context, auth.UserID, purchases.Scope, string, int) (syncapi.Page, error)
}

type syncHandler struct {
	service SyncUseCases
}

func (handler *syncHandler) register(mux *http.ServeMux, tokens *auth.TokenManager) {
	mux.Handle("GET /v1/sync", requireAccess(tokens, http.HandlerFunc(handler.page)))
}

func (handler *syncHandler) page(response http.ResponseWriter, request *http.Request) {
	claims, _ := accessClaims(request.Context())
	limit := 0
	var err error
	if rawLimit := request.URL.Query().Get("limit"); rawLimit != "" {
		limit, err = strconv.Atoi(rawLimit)
		if err != nil || limit <= 0 {
			writeAPIError(response, http.StatusBadRequest, "invalid_request", "Invalid request")
			return
		}
	}
	result, err := handler.service.Page(
		request.Context(), claims.UserID, purchaseScope(request),
		request.URL.Query().Get("cursor"), limit,
	)
	if err != nil {
		if errors.Is(err, syncapi.ErrInvalidCursor) || errors.Is(err, syncapi.ErrInvalidRequest) {
			writeAPIError(response, http.StatusBadRequest, "invalid_cursor", "Invalid sync cursor")
			return
		}
		writeAPIError(response, http.StatusInternalServerError, "internal_error", "Internal server error")
		return
	}
	writeJSON(response, http.StatusOK, result)
}
