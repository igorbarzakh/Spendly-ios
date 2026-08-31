package purchases

import (
	"context"
	"errors"
	"math"
	"testing"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

func TestCreateQuickPurchaseUsesAuthenticatedOwner(t *testing.T) {
	repository := &repositoryStub{create: func(_ context.Context, owner auth.UserID, draft Draft, _ string) (Purchase, error) {
		if owner != auth.UserID("11111111-1111-4111-8111-111111111111") {
			t.Fatalf("unexpected owner %s", owner)
		}
		return Purchase{ID: draft.ID, OwnerID: owner, Kind: KindQuick, AmountMinor: draft.AmountMinor, Version: 1}, nil
	}}
	service := NewService(repository)

	purchase, err := service.Create(context.Background(), auth.UserID("11111111-1111-4111-8111-111111111111"), validQuickDraft(), "idem-key")

	if err != nil {
		t.Fatalf("create purchase: %v", err)
	}
	if purchase.OwnerID == "" {
		t.Fatal("owner was not assigned")
	}
}

func TestCreateRejectsInvalidQuickAmount(t *testing.T) {
	service := NewService(&repositoryStub{})
	draft := validQuickDraft()
	draft.AmountMinor = 0

	_, err := service.Create(context.Background(), auth.UserID("user"), draft, "idem-key")

	if !errors.Is(err, ErrInvalidPurchase) {
		t.Fatalf("expected invalid purchase, got %v", err)
	}
}

func TestCreateRejectsEmptyDetailedPurchase(t *testing.T) {
	service := NewService(&repositoryStub{})
	draft := validQuickDraft()
	draft.Kind, draft.Category, draft.AmountMinor = KindDetailed, "", 0

	_, err := service.Create(context.Background(), auth.UserID("user"), draft, "idem-key")

	if !errors.Is(err, ErrInvalidPurchase) {
		t.Fatalf("expected invalid purchase, got %v", err)
	}
}

func TestDetailedTotalRejectsOverflow(t *testing.T) {
	draft := validQuickDraft()
	draft.Kind, draft.Category, draft.AmountMinor = KindDetailed, "", 0
	draft.Items = []ItemDraft{{ID: "item-1", Position: 0, Name: "One", Category: "Food", AmountMinor: math.MaxInt64}, {ID: "item-2", Position: 1, Name: "Two", Category: "Food", AmountMinor: 1}}

	_, err := draft.TotalMinor()

	if !errors.Is(err, ErrInvalidPurchase) {
		t.Fatalf("expected overflow rejection, got %v", err)
	}
}

func TestDetailedTotalIncludesDeliveryAndFixedDiscount(t *testing.T) {
	draft := validDetailedCartDraft()
	draft.DeliveryFeeMinor = 9900
	draft.Discount = &Discount{Type: DiscountFixed, Value: 5000}

	total, err := draft.TotalMinor()

	if err != nil {
		t.Fatalf("total: %v", err)
	}
	if total != 48400 {
		t.Fatalf("expected 48400, got %d", total)
	}
}

func TestDetailedPercentageDiscountAppliesOnlyToItems(t *testing.T) {
	draft := validDetailedCartDraft()
	draft.DeliveryFeeMinor = 9900
	draft.Discount = &Discount{Type: DiscountPercentage, Value: 10}

	total, err := draft.TotalMinor()

	if err != nil {
		t.Fatalf("total: %v", err)
	}
	if total != 49050 {
		t.Fatalf("expected 49050, got %d", total)
	}
}

func TestDetailedTotalDoesNotBecomeNegative(t *testing.T) {
	draft := validDetailedCartDraft()
	draft.Discount = &Discount{Type: DiscountFixed, Value: 999999}

	total, err := draft.TotalMinor()

	if err != nil {
		t.Fatalf("total: %v", err)
	}
	if total != 0 {
		t.Fatalf("expected clamped zero total, got %d", total)
	}
}

func TestDetailedCartItemTotalIsDerivedFromQuantityAndUnitPrice(t *testing.T) {
	draft := validDetailedCartDraft()
	draft.Items[0].AmountMinor = 1

	total, err := draft.TotalMinor()

	if err != nil {
		t.Fatalf("total: %v", err)
	}
	if total != 43500 {
		t.Fatalf("expected derived item totals to ignore stale amount_minor, got %d", total)
	}
}

func TestDetailedRejectsInvalidDiscount(t *testing.T) {
	draft := validDetailedCartDraft()
	draft.Discount = &Discount{Type: DiscountPercentage, Value: 101}

	_, err := draft.TotalMinor()

	if !errors.Is(err, ErrInvalidPurchase) {
		t.Fatalf("expected invalid purchase, got %v", err)
	}
}

func validQuickDraft() Draft {
	return Draft{ID: "22222222-2222-4222-8222-222222222222", Kind: KindQuick, Merchant: "Market", Category: "Food", AmountMinor: 12500, CurrencyCode: "RUB", SpentAt: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC), LocalDate: "2026-08-24", TimeZone: "Europe/Moscow"}
}

func validDetailedCartDraft() Draft {
	draft := validQuickDraft()
	draft.Kind, draft.Category, draft.AmountMinor = KindDetailed, "", 0
	draft.Items = []ItemDraft{
		{ID: "item-1", Position: 0, Name: "Milk", Category: "Food", Quantity: 2, UnitPriceMinor: 9500, AmountMinor: 19000},
		{ID: "item-2", Position: 1, Name: "Bread", Category: "Food", Quantity: 1, UnitPriceMinor: 8900, AmountMinor: 8900},
		{ID: "item-3", Position: 2, Name: "Bananas", Category: "Food", Quantity: 1, UnitPriceMinor: 15600, AmountMinor: 15600},
	}
	return draft
}

type repositoryStub struct {
	create func(context.Context, auth.UserID, Draft, string) (Purchase, error)
}

func (repository *repositoryStub) Create(ctx context.Context, owner auth.UserID, draft Draft, key string) (Purchase, error) {
	if repository.create == nil {
		return Purchase{}, errors.New("unexpected repository call")
	}
	return repository.create(ctx, owner, draft, key)
}
func (*repositoryStub) List(context.Context, auth.UserID, Scope, time.Time, time.Time) ([]Purchase, error) {
	return nil, nil
}
func (*repositoryStub) Update(context.Context, auth.UserID, Purchase, int64) (Purchase, error) {
	return Purchase{}, nil
}
func (*repositoryStub) Delete(context.Context, auth.UserID, string, int64) error { return nil }
