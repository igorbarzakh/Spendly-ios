package main

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestProbeHealthAcceptsSuccessfulLivenessResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.URL.Path != "/health/live" {
			t.Fatalf("unexpected path %q", request.URL.Path)
		}
		response.WriteHeader(http.StatusOK)
	}))
	defer server.Close()

	if err := probeHealth(context.Background(), server.URL+"/health/live"); err != nil {
		t.Fatalf("probe health: %v", err)
	}
}

func TestProbeHealthRejectsNonSuccessfulResponse(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, _ *http.Request) {
		response.WriteHeader(http.StatusServiceUnavailable)
	}))
	defer server.Close()

	if err := probeHealth(context.Background(), server.URL+"/health/live"); err == nil {
		t.Fatal("expected unhealthy response to fail")
	}
}
