package httpapi

import (
	"context"
	"net/http"
	"strings"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
)

type accessClaimsContextKey struct{}

func requireAccess(tokens *auth.TokenManager, next http.Handler) http.Handler {
	return http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		parts := strings.Fields(request.Header.Get("Authorization"))
		if len(parts) != 2 || parts[0] != "Bearer" {
			writeAPIError(response, http.StatusUnauthorized, "unauthorized", "Authentication required")
			return
		}
		claims, err := tokens.VerifyAccess(parts[1])
		if err != nil {
			writeAPIError(response, http.StatusUnauthorized, "unauthorized", "Authentication required")
			return
		}
		next.ServeHTTP(response, request.WithContext(context.WithValue(request.Context(), accessClaimsContextKey{}, claims)))
	})
}

func accessClaims(ctx context.Context) (auth.AccessClaims, bool) {
	claims, ok := ctx.Value(accessClaimsContextKey{}).(auth.AccessClaims)
	return claims, ok
}
