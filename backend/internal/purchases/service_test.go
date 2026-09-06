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

func TestListReturnsBoundedPageAndCursor(t *testing.T) {
	spentAt := time.Date(2026, 9, 7, 12, 0, 0, 0, time.UTC)
	values := []Purchase{
		{Draft: Draft{ID: "11111111-1111-4111-8111-111111111111", SpentAt: spentAt}},
		{Draft: Draft{ID: "22222222-2222-4222-8222-222222222222", SpentAt: spentAt.Add(-time.Hour)}},
		{Draft: Draft{ID: "33333333-3333-4333-8333-333333333333", SpentAt: spentAt.Add(-2 * time.Hour)}},
	}
	repository := &repositoryStub{list: func(_ context.Context, _ auth.UserID, _ Scope, query ListQuery) ([]Purchase, error) {
		if query.Limit != 3 {
			t.Fatalf("expected limit+1 repository query, got %d", query.Limit)
		}
		return values, nil
	}}
	service := NewService(repository)

	page, err := service.List(context.Background(), auth.UserID("user"), Scope{}, ListOptions{Limit: 2})

	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if len(page.Purchases) != 2 || !page.HasMore || page.NextCursor == "" {
		t.Fatalf("unexpected page: %+v", page)
	}
	decoded, err := DecodeListCursor(page.NextCursor)
	if err != nil {
		t.Fatalf("decode cursor: %v", err)
	}
	if decoded.SpentAt != values[1].SpentAt || decoded.ID != values[1].ID {
		t.Fatalf("cursor does not match last returned purchase: %+v", decoded)
	}
}

func TestListRejectsInvalidCursor(t *testing.T) {
	service := NewService(&repositoryStub{})

	_, err := service.List(context.Background(), auth.UserID("user"), Scope{}, ListOptions{Cursor: "not-a-cursor", Limit: 50})

	if !errors.Is(err, ErrInvalidCursor) {
		t.Fatalf("expected invalid cursor, got %v", err)
	}
}

func TestListReturnsEmptyArrayWhenRepositoryHasNoPurchases(t *testing.T) {
	repository := &repositoryStub{list: func(context.Context, auth.UserID, Scope, ListQuery) ([]Purchase, error) {
		return nil, nil
	}}
	service := NewService(repository)

	page, err := service.List(context.Background(), auth.UserID("user"), Scope{}, ListOptions{})

	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if page.Purchases == nil {
		t.Fatal("expected an empty purchases array, got nil")
	}
}

func TestListUsesDefaultAndMaximumPageSizes(t *testing.T) {
	tests := []struct {
		name          string
		requested     int
		repositoryMax int
	}{
		{name: "default", requested: 0, repositoryMax: 51},
		{name: "maximum", requested: 1_000, repositoryMax: 101},
	}
	for _, test := range tests {
		t.Run(test.name, func(t *testing.T) {
			repository := &repositoryStub{list: func(_ context.Context, _ auth.UserID, _ Scope, query ListQuery) ([]Purchase, error) {
				if query.Limit != test.repositoryMax {
					t.Fatalf("unexpected repository limit: %d", query.Limit)
				}
				return []Purchase{}, nil
			}}

			if _, err := NewService(repository).List(context.Background(), auth.UserID("user"), Scope{}, ListOptions{Limit: test.requested}); err != nil {
				t.Fatalf("list: %v", err)
			}
		})
	}
}

func TestListKeepsUnpaginatedDateRangeCompatible(t *testing.T) {
	from := time.Date(2026, 9, 1, 0, 0, 0, 0, time.UTC)
	to := from.AddDate(0, 1, 0)
	repository := &repositoryStub{list: func(_ context.Context, _ auth.UserID, _ Scope, query ListQuery) ([]Purchase, error) {
		if query.Limit != 0 {
			t.Fatalf("expected an unbounded interval query, got limit %d", query.Limit)
		}
		return []Purchase{}, nil
	}}

	page, err := NewService(repository).List(context.Background(), auth.UserID("user"), Scope{}, ListOptions{From: from, To: to})

	if err != nil {
		t.Fatalf("list: %v", err)
	}
	if page.HasMore || page.NextCursor != "" {
		t.Fatalf("unexpected pagination metadata: %+v", page)
	}
}

func validQuickDraft() Draft {
	return Draft{ID: "22222222-2222-4222-8222-222222222222", Kind: KindQuick, Merchant: "Market", Category: "Food", AmountMinor: 12500, CurrencyCode: "RUB", SpentAt: time.Date(2026, 8, 24, 12, 0, 0, 0, time.UTC), LocalDate: "2026-08-24", TimeZone: "Europe/Moscow"}
}

func validDetailedCartDraft() Draft {
	draft := validQuickDraft()
	draft.Kind, draft.Category, draft.AmountMinor = KindDetailed, "", 0
	draft.Items = []ItemDraft{
		{ID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa1", Position: 0, Name: "Milk", Category: "Food", Quantity: 2, UnitPriceMinor: 9500, AmountMinor: 19000},
		{ID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa2", Position: 1, Name: "Bread", Category: "Food", Quantity: 1, UnitPriceMinor: 8900, AmountMinor: 8900},
		{ID: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaa3", Position: 2, Name: "Bananas", Category: "Food", Quantity: 1, UnitPriceMinor: 15600, AmountMinor: 15600},
	}
	return draft
}

type repositoryStub struct {
	create func(context.Context, auth.UserID, Draft, string) (Purchase, error)
	list   func(context.Context, auth.UserID, Scope, ListQuery) ([]Purchase, error)
}

func (repository *repositoryStub) Create(ctx context.Context, owner auth.UserID, draft Draft, key string) (Purchase, error) {
	if repository.create == nil {
		return Purchase{}, errors.New("unexpected repository call")
	}
	return repository.create(ctx, owner, draft, key)
}
func (repository *repositoryStub) List(ctx context.Context, user auth.UserID, scope Scope, query ListQuery) ([]Purchase, error) {
	if repository.list == nil {
		return nil, errors.New("unexpected repository call")
	}
	return repository.list(ctx, user, scope, query)
}
func (*repositoryStub) Update(context.Context, auth.UserID, Purchase, int64) (Purchase, error) {
	return Purchase{}, nil
}
func (*repositoryStub) Delete(context.Context, auth.UserID, string, int64) error { return nil }
