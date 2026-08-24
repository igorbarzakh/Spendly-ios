package purchases

import (
	"errors"
	"math"
	"strings"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type Kind string

const (
	KindQuick    Kind = "quick"
	KindDetailed Kind = "detailed"
)

var (
	ErrInvalidPurchase     = errors.New("invalid purchase")
	ErrForbidden           = errors.New("purchase forbidden")
	ErrNotFound            = errors.New("purchase not found")
	ErrVersionConflict     = errors.New("purchase version conflict")
	ErrIdempotencyConflict = errors.New("idempotency conflict")
)

type ItemDraft struct {
	ID          string `json:"id"`
	Position    int    `json:"position"`
	Name        string `json:"name"`
	Category    string `json:"category"`
	AmountMinor int64  `json:"amount_minor"`
}
type Item struct {
	ItemDraft
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Draft struct {
	ID           string      `json:"id"`
	GroupID      *string     `json:"group_id,omitempty"`
	Kind         Kind        `json:"kind"`
	Merchant     string      `json:"merchant"`
	Category     string      `json:"category,omitempty"`
	AmountMinor  int64       `json:"amount_minor,omitempty"`
	CurrencyCode string      `json:"currency_code"`
	SpentAt      time.Time   `json:"spent_at"`
	LocalDate    string      `json:"local_date"`
	TimeZone     string      `json:"time_zone"`
	Items        []ItemDraft `json:"items,omitempty"`
}

type Purchase struct {
	Draft
	OwnerID          auth.UserID `json:"owner_id"`
	Version          int64       `json:"version"`
	TotalAmountMinor int64       `json:"total_amount_minor"`
	CreatedAt        time.Time   `json:"created_at"`
	UpdatedAt        time.Time   `json:"updated_at"`
	DeletedAt        *time.Time  `json:"deleted_at,omitempty"`
}

type Scope struct{ GroupID *string }

func (draft Draft) TotalMinor() (int64, error) {
	if draft.Kind == KindQuick {
		if draft.AmountMinor <= 0 {
			return 0, ErrInvalidPurchase
		}
		return draft.AmountMinor, nil
	}
	if draft.Kind != KindDetailed || len(draft.Items) == 0 {
		return 0, ErrInvalidPurchase
	}
	var total int64
	for index, item := range draft.Items {
		if item.AmountMinor <= 0 || strings.TrimSpace(item.Name) == "" || strings.TrimSpace(item.Category) == "" || item.Position != index || total > math.MaxInt64-item.AmountMinor {
			return 0, ErrInvalidPurchase
		}
		total += item.AmountMinor
	}
	return total, nil
}

func (draft Draft) validate() error {
	if draft.ID == "" || strings.TrimSpace(draft.Merchant) == "" || len(draft.CurrencyCode) != 3 || strings.ToUpper(draft.CurrencyCode) != draft.CurrencyCode || draft.SpentAt.IsZero() || draft.LocalDate == "" || strings.TrimSpace(draft.TimeZone) == "" {
		return ErrInvalidPurchase
	}
	if _, err := time.Parse("2006-01-02", draft.LocalDate); err != nil {
		return ErrInvalidPurchase
	}
	if _, err := time.LoadLocation(draft.TimeZone); err != nil {
		return ErrInvalidPurchase
	}
	if draft.Kind == KindQuick {
		if strings.TrimSpace(draft.Category) == "" || len(draft.Items) != 0 || draft.AmountMinor <= 0 {
			return ErrInvalidPurchase
		}
	} else if draft.Kind == KindDetailed {
		if draft.Category != "" || draft.AmountMinor != 0 {
			return ErrInvalidPurchase
		}
	} else {
		return ErrInvalidPurchase
	}
	_, err := draft.TotalMinor()
	return err
}
