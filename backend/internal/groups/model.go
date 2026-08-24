package groups

import (
	"errors"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"time"
)

var (
	ErrInvalidGroup          = errors.New("invalid group")
	ErrForbidden             = errors.New("group forbidden")
	ErrNotFound              = errors.New("group not found")
	ErrOwnerImmutable        = errors.New("group owner is immutable")
	ErrInvitationUnavailable = errors.New("invitation unavailable")
	ErrGroupArchived         = errors.New("group archived")
)

type Group struct {
	ID         string      `json:"id"`
	Name       string      `json:"name"`
	OwnerID    auth.UserID `json:"owner_id"`
	ArchivedAt *time.Time  `json:"archived_at,omitempty"`
	CreatedAt  time.Time   `json:"created_at"`
	UpdatedAt  time.Time   `json:"updated_at"`
}
type Member struct {
	UserID            auth.UserID `json:"user_id"`
	Role              string      `json:"role"`
	CanManageExpenses bool        `json:"can_manage_expenses"`
	JoinedAt          time.Time   `json:"joined_at"`
}
type Invitation struct {
	ID        string    `json:"id"`
	GroupID   string    `json:"group_id"`
	Token     string    `json:"token"`
	ExpiresAt time.Time `json:"expires_at"`
}
