package httpapi

import (
	"context"
	"errors"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

type readinessProbeFunc func(context.Context) error

func (probe readinessProbeFunc) Ping(ctx context.Context) error {
	return probe(ctx)
}

func TestLivenessReturnsJSON(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	response := httptest.NewRecorder()

	NewHandler(nil).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}
	if got := response.Header().Get("Content-Type"); got != "application/json" {
		t.Fatalf("expected JSON content type, got %q", got)
	}
	if got := strings.TrimSpace(response.Body.String()); got != `{"status":"ok"}` {
		t.Fatalf("unexpected body %q", got)
	}
}

func TestReadinessReturnsUnavailableWithoutDatabase(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health/ready", nil)
	response := httptest.NewRecorder()

	NewHandler(nil).ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", response.Code)
	}
}

func TestReadinessDoesNotExposeDatabaseError(t *testing.T) {
	probe := readinessProbeFunc(func(context.Context) error {
		return errors.New("password=do-not-leak")
	})
	request := httptest.NewRequest(http.MethodGet, "/health/ready", nil)
	response := httptest.NewRecorder()

	NewHandler(probe).ServeHTTP(response, request)

	if response.Code != http.StatusServiceUnavailable {
		t.Fatalf("expected 503, got %d", response.Code)
	}
	if strings.Contains(response.Body.String(), "do-not-leak") {
		t.Fatal("database error leaked into response")
	}
}

func TestReadinessBoundsDatabasePing(t *testing.T) {
	var hasDeadline bool
	probe := readinessProbeFunc(func(ctx context.Context) error {
		_, hasDeadline = ctx.Deadline()
		return nil
	})
	request := httptest.NewRequest(http.MethodGet, "/health/ready", nil)
	response := httptest.NewRecorder()

	NewHandler(probe).ServeHTTP(response, request)

	if response.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", response.Code)
	}
	if !hasDeadline {
		t.Fatal("expected database readiness probe to have a deadline")
	}
}

func TestRequestIDIsReturned(t *testing.T) {
	request := httptest.NewRequest(http.MethodGet, "/health/live", nil)
	request.Header.Set("X-Request-ID", "request-123")
	response := httptest.NewRecorder()

	NewHandler(nil).ServeHTTP(response, request)

	if got := response.Header().Get("X-Request-ID"); got != "request-123" {
		t.Fatalf("expected request ID to be preserved, got %q", got)
	}
}
