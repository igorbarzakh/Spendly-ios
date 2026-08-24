package sync

import (
	"errors"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

var (
	ErrInvalidCursor  = errors.New("invalid sync cursor")
	ErrInvalidRequest = errors.New("invalid sync request")
)

type Cursor struct {
	UpdatedAt time.Time `json:"updated_at"`
	ID        string    `json:"id"`
}

type Change struct {
	Purchase purchases.Purchase `json:"purchase"`
	Deleted  bool               `json:"deleted"`
}

type Page struct {
	Changes    []Change `json:"changes"`
	NextCursor string   `json:"next_cursor"`
}
