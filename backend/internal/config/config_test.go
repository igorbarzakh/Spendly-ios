package config

import (
	"errors"
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
