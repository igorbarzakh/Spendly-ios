package config

import (
	"errors"
	"os"
	"path/filepath"
	"testing"
	"time"
)

func TestLoadRejectsMissingDatabaseURL(t *testing.T) {
	setValidEnvironment(t)
	t.Setenv("DATABASE_URL", "")

	_, err := Load()

	if !errors.Is(err, ErrMissingDatabaseURL) {
		t.Fatalf("expected ErrMissingDatabaseURL, got %v", err)
	}
}

func TestLoadRejectsMissingSecretsAndClientIDs(t *testing.T) {
	tests := []struct {
		name string
		key  string
		want error
	}{
		{name: "signing key", key: "TOKEN_SIGNING_KEY", want: ErrMissingTokenSigningKey},
		{name: "Apple client ID", key: "APPLE_CLIENT_ID", want: ErrMissingAppleClientID},
		{name: "Google client ID", key: "GOOGLE_CLIENT_ID", want: ErrMissingGoogleClientID},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			setValidEnvironment(t)
			t.Setenv(tt.key, "")

			_, err := Load()

			if !errors.Is(err, tt.want) {
				t.Fatalf("expected %v, got %v", tt.want, err)
			}
		})
	}
}

func TestLoadRejectsNonPositiveTimeout(t *testing.T) {
	setValidEnvironment(t)
	t.Setenv("HTTP_READ_TIMEOUT", "0s")

	_, err := Load()

	if !errors.Is(err, ErrInvalidDuration) {
		t.Fatalf("expected ErrInvalidDuration, got %v", err)
	}
}

func TestLoadUsesSafeDefaults(t *testing.T) {
	setValidEnvironment(t)

	config, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	if config.HTTP.Address != ":8080" {
		t.Fatalf("expected :8080, got %q", config.HTTP.Address)
	}
	if config.HTTP.ReadHeaderTimeout != 5*time.Second {
		t.Fatalf("expected 5s read header timeout, got %s", config.HTTP.ReadHeaderTimeout)
	}
	if config.HTTP.ReadTimeout <= 0 || config.HTTP.WriteTimeout <= 0 || config.HTTP.IdleTimeout <= 0 {
		t.Fatal("all HTTP timeouts must be positive")
	}
}

func TestLoadReadsDotEnvFromWorkingDirectory(t *testing.T) {
	t.Setenv("DATABASE_URL", "")
	t.Setenv("TOKEN_SIGNING_KEY", "")
	t.Setenv("APPLE_CLIENT_ID", "")
	t.Setenv("GOOGLE_CLIENT_ID", "")
	t.Setenv("HTTP_ADDRESS", "")
	t.Setenv("HTTP_READ_HEADER_TIMEOUT", "")
	t.Setenv("HTTP_READ_TIMEOUT", "")
	t.Setenv("HTTP_WRITE_TIMEOUT", "")
	t.Setenv("HTTP_IDLE_TIMEOUT", "")
	t.Chdir(t.TempDir())
	content := []byte(`
DATABASE_URL=postgres://spendly:secret@localhost:55432/spendly_test?sslmode=disable
TOKEN_SIGNING_KEY=test-signing-key
APPLE_CLIENT_ID=app.spendly.ios
GOOGLE_CLIENT_ID=google-client-id
HTTP_ADDRESS=:9090
`)
	if err := os.WriteFile(filepath.Join(".", ".env"), content, 0o600); err != nil {
		t.Fatalf("write .env: %v", err)
	}

	config, err := Load()
	if err != nil {
		t.Fatalf("load config: %v", err)
	}

	if config.TokenSigningKey != "test-signing-key" {
		t.Fatalf("expected token signing key from .env, got %q", config.TokenSigningKey)
	}
	if config.HTTP.Address != ":9090" {
		t.Fatalf("expected HTTP address from .env, got %q", config.HTTP.Address)
	}
}

func setValidEnvironment(t *testing.T) {
	t.Helper()
	t.Setenv("DATABASE_URL", "postgres://spendly:secret@postgres/spendly")
	t.Setenv("TOKEN_SIGNING_KEY", "test-signing-key")
	t.Setenv("APPLE_CLIENT_ID", "app.spendly.ios")
	t.Setenv("GOOGLE_CLIENT_ID", "google-client-id")
	t.Setenv("HTTP_ADDRESS", "")
	t.Setenv("HTTP_READ_HEADER_TIMEOUT", "")
	t.Setenv("HTTP_READ_TIMEOUT", "")
	t.Setenv("HTTP_WRITE_TIMEOUT", "")
	t.Setenv("HTTP_IDLE_TIMEOUT", "")
}
