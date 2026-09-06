package purchases

import (
	"context"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type Repository interface {
	Create(context.Context, auth.UserID, Draft, string) (Purchase, error)
	List(context.Context, auth.UserID, Scope, ListQuery) ([]Purchase, error)
	Update(context.Context, auth.UserID, Purchase, int64) (Purchase, error)
	Delete(context.Context, auth.UserID, string, int64) error
}

type Service struct{ repository Repository }

func NewService(repository Repository) *Service { return &Service{repository: repository} }

func (service *Service) Create(ctx context.Context, owner auth.UserID, draft Draft, idempotencyKey string) (Purchase, error) {
	if owner == "" || idempotencyKey == "" || draft.validate() != nil {
		return Purchase{}, ErrInvalidPurchase
	}
	return service.repository.Create(ctx, owner, draft, idempotencyKey)
}
func (service *Service) List(ctx context.Context, user auth.UserID, scope Scope, options ListOptions) (Page, error) {
	if user == "" || options.From.IsZero() != options.To.IsZero() || (!options.From.IsZero() && !options.To.After(options.From)) {
		return Page{}, ErrInvalidPurchase
	}
	paginated := options.From.IsZero() || options.Cursor != "" || options.Limit > 0
	if paginated {
		if options.Limit <= 0 {
			options.Limit = 50
		}
		if options.Limit > 100 {
			options.Limit = 100
		}
	}
	var cursor *ListCursor
	if options.Cursor != "" {
		decoded, err := DecodeListCursor(options.Cursor)
		if err != nil {
			return Page{}, err
		}
		cursor = &decoded
	}
	repositoryLimit := 0
	if paginated {
		repositoryLimit = options.Limit + 1
	}
	values, err := service.repository.List(ctx, user, scope, ListQuery{
		From: options.From, To: options.To, After: cursor, Limit: repositoryLimit,
	})
	if err != nil {
		return Page{}, err
	}
	if values == nil {
		values = []Purchase{}
	}
	hasMore := paginated && len(values) > options.Limit
	if hasMore {
		values = values[:options.Limit]
	}
	page := Page{Purchases: values, HasMore: hasMore}
	if hasMore {
		last := values[len(values)-1]
		page.NextCursor, err = EncodeListCursor(ListCursor{SpentAt: last.SpentAt, ID: last.ID})
		if err != nil {
			return Page{}, err
		}
	}
	return page, nil
}
func (service *Service) Update(ctx context.Context, user auth.UserID, purchase Purchase, expected int64) (Purchase, error) {
	if user == "" || expected <= 0 || purchase.Draft.validate() != nil {
		return Purchase{}, ErrInvalidPurchase
	}
	return service.repository.Update(ctx, user, purchase, expected)
}
func (service *Service) Delete(ctx context.Context, user auth.UserID, id string, expected int64) error {
	if user == "" || id == "" || expected <= 0 {
		return ErrInvalidPurchase
	}
	return service.repository.Delete(ctx, user, id, expected)
}
