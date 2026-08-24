package main

import (
	"context"
	"errors"
	"net/http"
	"os"
	"os/signal"
	"syscall"
	"time"

	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/config"
	"github.com/igorbarzakh/spendly-ios/backend/internal/groups"
	"github.com/igorbarzakh/spendly-ios/backend/internal/httpapi"
	"github.com/igorbarzakh/spendly-ios/backend/internal/observability"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/purchases"
)

func main() {
	logger := observability.NewLogger()
	settings, err := config.Load()
	if err != nil {
		logger.Error("invalid configuration", "error", err)
		os.Exit(1)
	}
	pool, err := postgres.NewPool(context.Background(), settings.DatabaseURL)
	if err != nil {
		logger.Error("database connection failed", "error", err)
		os.Exit(1)
	}
	defer pool.Close()
	database := postgres.NewDB(pool)
	privateKey, publicKey, err := auth.ParseSigningKey(settings.TokenSigningKey)
	if err != nil {
		logger.Error("invalid token signing key", "error", err)
		os.Exit(1)
	}
	tokenManager := auth.NewTokenManager(privateKey, publicKey, "spendly-api", "spendly-ios", 15*time.Minute, time.Now)
	providerClient := &http.Client{Timeout: 5 * time.Second}
	verifiers := map[auth.Provider]auth.IdentityVerifier{
		auth.ProviderApple: auth.NewOIDCVerifier(auth.OIDCConfig{
			Provider: auth.ProviderApple, Issuer: "https://appleid.apple.com", Audience: settings.AppleClientID,
			JWKSURL: "https://appleid.apple.com/auth/keys", CacheTTL: time.Hour,
		}, providerClient, time.Now),
		auth.ProviderGoogle: auth.NewOIDCVerifier(auth.OIDCConfig{
			Provider: auth.ProviderGoogle, Issuer: "https://accounts.google.com", Audience: settings.GoogleClientID,
			JWKSURL: "https://www.googleapis.com/oauth2/v3/certs", CacheTTL: time.Hour,
		}, providerClient, time.Now),
	}
	sessionService := auth.NewSessionService(auth.NewSessionRepository(pool), tokenManager, 30*24*time.Hour, time.Now)
	authService := auth.NewAuthService(verifiers, auth.NewIdentityRepository(pool), sessionService)
	purchaseService := purchases.NewService(purchases.NewPostgresRepository(pool))
	groupService := groups.NewService(groups.NewPostgresRepository(pool, time.Now))

	server := &http.Server{
		Addr:              settings.HTTP.Address,
		Handler:           httpapi.NewHandler(database, httpapi.WithAuth(authService, tokenManager), httpapi.WithPurchases(purchaseService), httpapi.WithGroups(groupService)),
		ReadHeaderTimeout: settings.HTTP.ReadHeaderTimeout,
		ReadTimeout:       settings.HTTP.ReadTimeout,
		WriteTimeout:      settings.HTTP.WriteTimeout,
		IdleTimeout:       settings.HTTP.IdleTimeout,
	}

	shutdownContext, stop := signal.NotifyContext(context.Background(), os.Interrupt, syscall.SIGTERM)
	defer stop()

	go func() {
		<-shutdownContext.Done()
		context, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		if err := server.Shutdown(context); err != nil {
			logger.Error("graceful shutdown failed", "error", err)
		}
	}()

	logger.Info("HTTP server starting", "address", settings.HTTP.Address)
	if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		logger.Error("HTTP server stopped", "error", err)
		os.Exit(1)
	}
}
