package purchases

import (
	"encoding/base64"
	"encoding/json"
	"errors"
	"math"
	"regexp"
	"strings"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type Kind string
type DiscountType string

const (
	KindQuick    Kind = "quick"
	KindDetailed Kind = "detailed"

	DiscountFixed      DiscountType = "fixed"
	DiscountPercentage DiscountType = "percentage"
)

var (
	ErrInvalidPurchase     = errors.New("invalid purchase")
	ErrForbidden           = errors.New("purchase forbidden")
	ErrNotFound            = errors.New("purchase not found")
	ErrVersionConflict     = errors.New("purchase version conflict")
	ErrIdempotencyConflict = errors.New("idempotency conflict")
	ErrInvalidCursor       = errors.New("invalid purchase cursor")
)

var canonicalUUID = regexp.MustCompile(`(?i)^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$`)

type ItemDraft struct {
	ID             string `json:"id"`
	Position       int    `json:"position"`
	Name           string `json:"name"`
	Category       string `json:"category"`
	Quantity       int64  `json:"quantity,omitempty"`
	UnitPriceMinor int64  `json:"unit_price_minor,omitempty"`
	AmountMinor    int64  `json:"amount_minor"`
}
type Item struct {
	ItemDraft
	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

type Discount struct {
	Type  DiscountType `json:"type"`
	Value int64        `json:"value"`
}

type Draft struct {
	ID               string      `json:"id"`
	GroupID          *string     `json:"group_id,omitempty"`
	Kind             Kind        `json:"kind"`
	Merchant         string      `json:"merchant"`
	Category         string      `json:"category,omitempty"`
	AmountMinor      int64       `json:"amount_minor,omitempty"`
	CurrencyCode     string      `json:"currency_code"`
	SpentAt          time.Time   `json:"spent_at"`
	LocalDate        string      `json:"local_date"`
	TimeZone         string      `json:"time_zone"`
	DeliveryFeeMinor int64       `json:"delivery_fee_minor,omitempty"`
	Discount         *Discount   `json:"discount,omitempty"`
	Items            []ItemDraft `json:"items,omitempty"`
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

type ListOptions struct {
	From   time.Time
	To     time.Time
	Cursor string
	Limit  int
}

type ListCursor struct {
	SpentAt time.Time `json:"spent_at"`
	ID      string    `json:"id"`
}

type ListQuery struct {
	From  time.Time
	To    time.Time
	After *ListCursor
	Limit int
}

type Page struct {
	Purchases  []Purchase `json:"purchases"`
	NextCursor string     `json:"next_cursor,omitempty"`
	HasMore    bool       `json:"has_more"`
}

func EncodeListCursor(cursor ListCursor) (string, error) {
	if cursor.SpentAt.IsZero() || !canonicalUUID.MatchString(cursor.ID) {
		return "", ErrInvalidCursor
	}
	payload, err := json.Marshal(cursor)
	if err != nil {
		return "", ErrInvalidCursor
	}
	return base64.RawURLEncoding.EncodeToString(payload), nil
}

func DecodeListCursor(raw string) (ListCursor, error) {
	payload, err := base64.RawURLEncoding.DecodeString(raw)
	if err != nil {
		return ListCursor{}, ErrInvalidCursor
	}
	var cursor ListCursor
	if json.Unmarshal(payload, &cursor) != nil || cursor.SpentAt.IsZero() || !canonicalUUID.MatchString(cursor.ID) {
		return ListCursor{}, ErrInvalidCursor
	}
	return cursor, nil
}

func (draft Draft) TotalMinor() (int64, error) {
	if draft.Kind == KindQuick {
		if draft.AmountMinor <= 0 || draft.DeliveryFeeMinor != 0 || draft.Discount != nil || len(draft.Items) != 0 {
			return 0, ErrInvalidPurchase
		}
		return draft.AmountMinor, nil
	}
	if draft.Kind != KindDetailed || len(draft.Items) == 0 {
		return 0, ErrInvalidPurchase
	}
	var total int64
	for index, item := range draft.Items {
		amount, err := item.TotalMinor()
		if err != nil || strings.TrimSpace(item.Name) == "" || strings.TrimSpace(item.Category) == "" || item.Position != index || total > math.MaxInt64-amount {
			return 0, ErrInvalidPurchase
		}
		total += amount
	}
	if draft.DeliveryFeeMinor < 0 || total > math.MaxInt64-draft.DeliveryFeeMinor {
		return 0, ErrInvalidPurchase
	}
	discount, err := draft.DiscountAmountMinor(total)
	if err != nil {
		return 0, err
	}
	result := total + draft.DeliveryFeeMinor - discount
	if result < 0 {
		return 0, nil
	}
	return result, nil
}

func (draft Draft) DiscountAmountMinor(itemsSubtotal int64) (int64, error) {
	if draft.Discount == nil {
		return 0, nil
	}
	if itemsSubtotal < 0 || draft.Discount.Value < 0 {
		return 0, ErrInvalidPurchase
	}
	switch draft.Discount.Type {
	case DiscountFixed:
		return draft.Discount.Value, nil
	case DiscountPercentage:
		if draft.Discount.Value > 100 {
			return 0, ErrInvalidPurchase
		}
		return itemsSubtotal * draft.Discount.Value / 100, nil
	default:
		return 0, ErrInvalidPurchase
	}
}

func (item ItemDraft) TotalMinor() (int64, error) {
	if item.UnitPriceMinor == 0 {
		if item.Quantity < 0 || item.AmountMinor <= 0 {
			return 0, ErrInvalidPurchase
		}
		return item.AmountMinor, nil
	}
	if item.Quantity <= 0 || item.UnitPriceMinor <= 0 || item.Quantity > math.MaxInt64/item.UnitPriceMinor {
		return 0, ErrInvalidPurchase
	}
	return item.Quantity * item.UnitPriceMinor, nil
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
