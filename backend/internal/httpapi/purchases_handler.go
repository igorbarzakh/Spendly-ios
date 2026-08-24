package httpapi

import (
	"context"
	"errors"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
	"net/http"
	"strconv"
	"time"
)

type PurchaseUseCases interface {
	Create(context.Context, auth.UserID, purchases.Draft, string) (purchases.Purchase, error)
	List(context.Context, auth.UserID, purchases.Scope, time.Time, time.Time) ([]purchases.Purchase, error)
	Update(context.Context, auth.UserID, purchases.Purchase, int64) (purchases.Purchase, error)
	Delete(context.Context, auth.UserID, string, int64) error
}
type purchasesHandler struct{ service PurchaseUseCases }

func (h *purchasesHandler) register(m *http.ServeMux, t *auth.TokenManager) {
	m.Handle("POST /v1/purchases", requireAccess(t, http.HandlerFunc(h.create)))
	m.Handle("GET /v1/purchases", requireAccess(t, http.HandlerFunc(h.list)))
	m.Handle("PUT /v1/purchases/{id}", requireAccess(t, http.HandlerFunc(h.update)))
	m.Handle("DELETE /v1/purchases/{id}", requireAccess(t, http.HandlerFunc(h.delete)))
}
func (h *purchasesHandler) create(w http.ResponseWriter, r *http.Request) {
	claims, _ := accessClaims(r.Context())
	var draft purchases.Draft
	if decodeJSON(r, &draft) != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	value, err := h.service.Create(r.Context(), claims.UserID, draft, r.Header.Get("Idempotency-Key"))
	if err != nil {
		handlePurchaseError(w, err)
		return
	}
	writeJSON(w, 201, value)
}
func (h *purchasesHandler) list(w http.ResponseWriter, r *http.Request) {
	claims, _ := accessClaims(r.Context())
	from, e1 := time.Parse(time.RFC3339, r.URL.Query().Get("from"))
	to, e2 := time.Parse(time.RFC3339, r.URL.Query().Get("to"))
	scope := purchaseScope(r)
	if e1 != nil || e2 != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	values, err := h.service.List(r.Context(), claims.UserID, scope, from, to)
	if err != nil {
		handlePurchaseError(w, err)
		return
	}
	writeJSON(w, 200, map[string]any{"purchases": values})
}

func purchaseScope(request *http.Request) purchases.Scope {
	var scope purchases.Scope
	if group := request.URL.Query().Get("group_id"); group != "" {
		scope.GroupID = &group
	}
	return scope
}
func (h *purchasesHandler) update(w http.ResponseWriter, r *http.Request) {
	claims, _ := accessClaims(r.Context())
	var value purchases.Purchase
	if decodeJSON(r, &value) != nil || value.ID != r.PathValue("id") {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	version, err := strconv.ParseInt(r.Header.Get("If-Match"), 10, 64)
	if err != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	updated, err := h.service.Update(r.Context(), claims.UserID, value, version)
	if err != nil {
		handlePurchaseError(w, err)
		return
	}
	writeJSON(w, 200, updated)
}
func (h *purchasesHandler) delete(w http.ResponseWriter, r *http.Request) {
	claims, _ := accessClaims(r.Context())
	version, err := strconv.ParseInt(r.Header.Get("If-Match"), 10, 64)
	if err == nil {
		err = h.service.Delete(r.Context(), claims.UserID, r.PathValue("id"), version)
	}
	if err != nil {
		handlePurchaseError(w, err)
		return
	}
	w.WriteHeader(204)
}
func handlePurchaseError(w http.ResponseWriter, err error) {
	switch {
	case errors.Is(err, purchases.ErrInvalidPurchase):
		writeAPIError(w, 400, "invalid_purchase", "Invalid purchase")
	case errors.Is(err, purchases.ErrForbidden):
		writeAPIError(w, 403, "forbidden", "Forbidden")
	case errors.Is(err, purchases.ErrNotFound):
		writeAPIError(w, 404, "not_found", "Purchase not found")
	case errors.Is(err, purchases.ErrVersionConflict):
		writeAPIError(w, 409, "version_conflict", "Purchase changed")
	case errors.Is(err, purchases.ErrIdempotencyConflict):
		writeAPIError(w, 409, "idempotency_conflict", "Idempotency key conflict")
	default:
		writeAPIError(w, 500, "internal_error", "Internal server error")
	}
}
