package httpapi

import (
	"context"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/groups"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"
)

func TestCreateGroupUsesAuthenticatedOwner(t *testing.T) {
	manager := httpTestTokenManager(t)
	raw, _, _ := manager.IssueAccess("11111111-1111-4111-8111-111111111111", "22222222-2222-4222-8222-222222222222")
	stub := &groupUseCasesStub{create: func(_ context.Context, u auth.UserID, id, name string) (groups.Group, error) {
		if u != "11111111-1111-4111-8111-111111111111" || name != "Family" {
			t.Fatalf("unexpected input")
		}
		return groups.Group{ID: id, Name: name, OwnerID: u}, nil
	}}
	request := httptest.NewRequest(http.MethodPost, "/v1/groups", strings.NewReader(`{"id":"33333333-3333-4333-8333-333333333333","name":"Family"}`))
	request.Header.Set("Authorization", "Bearer "+raw)
	response := httptest.NewRecorder()
	NewHandler(nil, WithAuth(&authServiceStub{}, manager), WithGroups(stub)).ServeHTTP(response, request)
	if response.Code != 201 {
		t.Fatalf("expected 201, got %d: %s", response.Code, response.Body.String())
	}
}

type groupUseCasesStub struct {
	create func(context.Context, auth.UserID, string, string) (groups.Group, error)
}

func (s *groupUseCasesStub) Create(c context.Context, u auth.UserID, id, n string) (groups.Group, error) {
	return s.create(c, u, id, n)
}
func (*groupUseCasesStub) List(context.Context, auth.UserID) ([]groups.Group, error) { return nil, nil }
func (*groupUseCasesStub) Archive(context.Context, auth.UserID, string) error        { return nil }
func (*groupUseCasesStub) UpdateMember(context.Context, auth.UserID, string, auth.UserID, bool) error {
	return nil
}
func (*groupUseCasesStub) CreateInvitation(context.Context, auth.UserID, string, time.Duration) (groups.Invitation, error) {
	return groups.Invitation{}, nil
}
func (*groupUseCasesStub) AcceptInvitation(context.Context, auth.UserID, string) error { return nil }
func (*groupUseCasesStub) RevokeInvitation(context.Context, auth.UserID, string, string) error {
	return nil
}
