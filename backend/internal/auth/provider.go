package auth

import (
	"context"
	"errors"
)

type Provider string

const (
	ProviderApple  Provider = "apple"
	ProviderGoogle Provider = "google"
)

var (
	ErrInvalidIdentityToken        = errors.New("invalid identity token")
	ErrIdentityProviderUnavailable = errors.New("identity provider unavailable")
)

type Identity struct {
	Provider Provider
	Subject  string
	Email    string
	Name     string
}

type IdentityVerifier interface {
	Verify(context.Context, string, string) (Identity, error)
}
