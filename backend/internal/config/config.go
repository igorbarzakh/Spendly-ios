package config

import (
	"errors"
	"fmt"
	"os"
	"strings"
	"time"
)

var (
	ErrMissingDatabaseURL     = errors.New("DATABASE_URL is required")
	ErrMissingTokenSigningKey = errors.New("TOKEN_SIGNING_KEY is required")
	ErrMissingAppleClientID   = errors.New("APPLE_CLIENT_ID is required")
	ErrMissingGoogleClientID  = errors.New("GOOGLE_CLIENT_ID is required")
	ErrInvalidDuration        = errors.New("HTTP timeout must be a positive duration")
)

type Config struct {
	DatabaseURL     string
	TokenSigningKey string
	AppleClientID   string
	GoogleClientID  string
	HTTP            HTTPConfig
}

type HTTPConfig struct {
	Address           string
	ReadHeaderTimeout time.Duration
	ReadTimeout       time.Duration
	WriteTimeout      time.Duration
	IdleTimeout       time.Duration
}

func Load() (Config, error) {
	if err := loadDotEnv(".env"); err != nil {
		return Config{}, err
	}

	config := Config{
		DatabaseURL:     strings.TrimSpace(os.Getenv("DATABASE_URL")),
		TokenSigningKey: strings.TrimSpace(os.Getenv("TOKEN_SIGNING_KEY")),
		AppleClientID:   strings.TrimSpace(os.Getenv("APPLE_CLIENT_ID")),
		GoogleClientID:  strings.TrimSpace(os.Getenv("GOOGLE_CLIENT_ID")),
	}

	if config.DatabaseURL == "" {
		return Config{}, ErrMissingDatabaseURL
	}
	if config.TokenSigningKey == "" {
		return Config{}, ErrMissingTokenSigningKey
	}
	if config.AppleClientID == "" {
		return Config{}, ErrMissingAppleClientID
	}
	if config.GoogleClientID == "" {
		return Config{}, ErrMissingGoogleClientID
	}

	address := strings.TrimSpace(os.Getenv("HTTP_ADDRESS"))
	if address == "" {
		address = ":8080"
	}

	var err error
	config.HTTP = HTTPConfig{Address: address}
	if config.HTTP.ReadHeaderTimeout, err = positiveDuration("HTTP_READ_HEADER_TIMEOUT", 5*time.Second); err != nil {
		return Config{}, err
	}
	if config.HTTP.ReadTimeout, err = positiveDuration("HTTP_READ_TIMEOUT", 15*time.Second); err != nil {
		return Config{}, err
	}
	if config.HTTP.WriteTimeout, err = positiveDuration("HTTP_WRITE_TIMEOUT", 30*time.Second); err != nil {
		return Config{}, err
	}
	if config.HTTP.IdleTimeout, err = positiveDuration("HTTP_IDLE_TIMEOUT", 60*time.Second); err != nil {
		return Config{}, err
	}

	return config, nil
}

func positiveDuration(key string, fallback time.Duration) (time.Duration, error) {
	raw := strings.TrimSpace(os.Getenv(key))
	if raw == "" {
		return fallback, nil
	}

	value, err := time.ParseDuration(raw)
	if err != nil || value <= 0 {
		return 0, fmt.Errorf("%w: %s", ErrInvalidDuration, key)
	}
	return value, nil
}

func loadDotEnv(path string) error {
	content, err := os.ReadFile(path)
	if err != nil {
		if errors.Is(err, os.ErrNotExist) {
			return nil
		}
		return fmt.Errorf("read %s: %w", path, err)
	}

	for index, rawLine := range strings.Split(string(content), "\n") {
		line := strings.TrimSpace(rawLine)
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		line = strings.TrimPrefix(line, "export ")
		key, value, ok := strings.Cut(line, "=")
		if !ok {
			return fmt.Errorf("parse %s line %d: missing '='", path, index+1)
		}
		key = strings.TrimSpace(key)
		if key == "" || strings.ContainsAny(key, " \t") {
			return fmt.Errorf("parse %s line %d: invalid key", path, index+1)
		}
		if existing := strings.TrimSpace(os.Getenv(key)); existing != "" {
			continue
		}
		value = strings.TrimSpace(value)
		value = strings.Trim(value, `"'`)
		if err := os.Setenv(key, value); err != nil {
			return fmt.Errorf("set %s from %s: %w", key, path, err)
		}
	}
	return nil
}
