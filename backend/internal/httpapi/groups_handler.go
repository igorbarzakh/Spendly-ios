package httpapi

import (
	"context"
	"errors"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/groups"
	"net/http"
	"time"
)

type GroupUseCases interface {
	Create(context.Context, auth.UserID, string, string) (groups.Group, error)
	List(context.Context, auth.UserID) ([]groups.Group, error)
	Archive(context.Context, auth.UserID, string) error
	UpdateMember(context.Context, auth.UserID, string, auth.UserID, bool) error
	CreateInvitation(context.Context, auth.UserID, string, time.Duration) (groups.Invitation, error)
	AcceptInvitation(context.Context, auth.UserID, string) error
	RevokeInvitation(context.Context, auth.UserID, string, string) error
}
type groupsHandler struct{ service GroupUseCases }

func (h *groupsHandler) register(m *http.ServeMux, t *auth.TokenManager) {
	wrap := func(f http.HandlerFunc) http.Handler { return requireAccess(t, f) }
	m.Handle("GET /v1/groups", wrap(h.list))
	m.Handle("POST /v1/groups", wrap(h.create))
	m.Handle("PATCH /v1/groups/{id}", wrap(h.archive))
	m.Handle("PATCH /v1/groups/{id}/members/{userID}", wrap(h.member))
	m.Handle("POST /v1/groups/{id}/invitations", wrap(h.invite))
	m.Handle("POST /v1/group-invitations/{token}/accept", wrap(h.accept))
	m.Handle("DELETE /v1/groups/{id}/invitations/{invitationID}", wrap(h.revoke))
}
func (h *groupsHandler) create(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	var in struct {
		ID   string `json:"id"`
		Name string `json:"name"`
	}
	if decodeJSON(r, &in) != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	g, e := h.service.Create(r.Context(), c.UserID, in.ID, in.Name)
	if e != nil {
		handleGroupError(w, e)
		return
	}
	writeJSON(w, 201, g)
}
func (h *groupsHandler) list(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	v, e := h.service.List(r.Context(), c.UserID)
	if e != nil {
		handleGroupError(w, e)
		return
	}
	writeJSON(w, 200, map[string]any{"groups": v})
}
func (h *groupsHandler) archive(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	var in struct {
		Archived bool `json:"archived"`
	}
	if decodeJSON(r, &in) != nil || !in.Archived {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	if e := h.service.Archive(r.Context(), c.UserID, r.PathValue("id")); e != nil {
		handleGroupError(w, e)
		return
	}
	w.WriteHeader(204)
}
func (h *groupsHandler) member(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	var in struct {
		CanManage bool `json:"can_manage_expenses"`
	}
	if decodeJSON(r, &in) != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	if e := h.service.UpdateMember(r.Context(), c.UserID, r.PathValue("id"), auth.UserID(r.PathValue("userID")), in.CanManage); e != nil {
		handleGroupError(w, e)
		return
	}
	w.WriteHeader(204)
}
func (h *groupsHandler) invite(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	var in struct {
		ExpiresInSeconds int64 `json:"expires_in_seconds"`
	}
	if decodeJSON(r, &in) != nil {
		writeAPIError(w, 400, "invalid_request", "Invalid request")
		return
	}
	v, e := h.service.CreateInvitation(r.Context(), c.UserID, r.PathValue("id"), time.Duration(in.ExpiresInSeconds)*time.Second)
	if e != nil {
		handleGroupError(w, e)
		return
	}
	writeJSON(w, 201, v)
}
func (h *groupsHandler) accept(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	if e := h.service.AcceptInvitation(r.Context(), c.UserID, r.PathValue("token")); e != nil {
		handleGroupError(w, e)
		return
	}
	w.WriteHeader(204)
}
func (h *groupsHandler) revoke(w http.ResponseWriter, r *http.Request) {
	c, _ := accessClaims(r.Context())
	if e := h.service.RevokeInvitation(r.Context(), c.UserID, r.PathValue("id"), r.PathValue("invitationID")); e != nil {
		handleGroupError(w, e)
		return
	}
	w.WriteHeader(204)
}
func handleGroupError(w http.ResponseWriter, e error) {
	switch {
	case errors.Is(e, groups.ErrInvalidGroup):
		writeAPIError(w, 400, "invalid_group", "Invalid group")
	case errors.Is(e, groups.ErrForbidden), errors.Is(e, groups.ErrOwnerImmutable):
		writeAPIError(w, 403, "forbidden", "Forbidden")
	case errors.Is(e, groups.ErrNotFound):
		writeAPIError(w, 404, "not_found", "Group not found")
	case errors.Is(e, groups.ErrInvitationUnavailable), errors.Is(e, groups.ErrGroupArchived):
		writeAPIError(w, 409, "invitation_unavailable", "Invitation unavailable")
	default:
		writeAPIError(w, 500, "internal_error", "Internal server error")
	}
}
