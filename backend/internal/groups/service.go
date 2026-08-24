package groups

import (
	"context"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"strings"
	"time"
)

type Repository interface {
	Create(context.Context, auth.UserID, string, string) (Group, error)
	List(context.Context, auth.UserID) ([]Group, error)
	Archive(context.Context, auth.UserID, string) error
	UpdateMember(context.Context, auth.UserID, string, auth.UserID, bool) error
	CreateInvitation(context.Context, auth.UserID, string, time.Duration) (Invitation, error)
	AcceptInvitation(context.Context, auth.UserID, string) error
	RevokeInvitation(context.Context, auth.UserID, string, string) error
}
type Service struct{ repository Repository }

func NewService(r Repository) *Service { return &Service{r} }
func (s *Service) Create(c context.Context, u auth.UserID, id, n string) (Group, error) {
	if strings.TrimSpace(n) == "" {
		return Group{}, ErrInvalidGroup
	}
	return s.repository.Create(c, u, id, n)
}
func (s *Service) List(c context.Context, u auth.UserID) ([]Group, error) {
	return s.repository.List(c, u)
}
func (s *Service) Archive(c context.Context, u auth.UserID, id string) error {
	return s.repository.Archive(c, u, id)
}
func (s *Service) UpdateMember(c context.Context, u auth.UserID, g string, t auth.UserID, m bool) error {
	return s.repository.UpdateMember(c, u, g, t, m)
}
func (s *Service) CreateInvitation(c context.Context, u auth.UserID, g string, ttl time.Duration) (Invitation, error) {
	return s.repository.CreateInvitation(c, u, g, ttl)
}
func (s *Service) AcceptInvitation(c context.Context, u auth.UserID, t string) error {
	return s.repository.AcceptInvitation(c, u, t)
}
func (s *Service) RevokeInvitation(c context.Context, u auth.UserID, g, id string) error {
	return s.repository.RevokeInvitation(c, u, g, id)
}
