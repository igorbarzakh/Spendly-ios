package httpapi

import (
	"context"
	"errors"
	"net/http"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"github.com/igorbarzakh/spendly-ios/backend/internal/statistics"
)

type StatisticsUseCases interface {
	Monthly(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) (statistics.MonthlyResult, error)
}

type statisticsHandler struct {
	service StatisticsUseCases
}

func (handler *statisticsHandler) register(mux *http.ServeMux, tokens *auth.TokenManager) {
	mux.Handle("GET /v1/statistics", requireAccess(tokens, http.HandlerFunc(handler.monthly)))
}

func (handler *statisticsHandler) monthly(response http.ResponseWriter, request *http.Request) {
	claims, _ := accessClaims(request.Context())
	from, fromErr := time.Parse(time.RFC3339, request.URL.Query().Get("from"))
	to, toErr := time.Parse(time.RFC3339, request.URL.Query().Get("to"))
	if fromErr != nil || toErr != nil {
		writeAPIError(response, http.StatusBadRequest, "invalid_request", "Invalid request")
		return
	}
	scope := purchaseScope(request)
	result, err := handler.service.Monthly(request.Context(), claims.UserID, scope, from, to)
	if err != nil {
		if errors.Is(err, statistics.ErrInvalidRange) {
			writeAPIError(response, http.StatusBadRequest, "invalid_range", "Invalid statistics range")
			return
		}
		writeAPIError(response, http.StatusInternalServerError, "internal_error", "Internal server error")
		return
	}
	writeJSON(response, http.StatusOK, result)
}
