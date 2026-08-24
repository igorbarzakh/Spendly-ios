#!/bin/sh
set -eu

export TEST_DATABASE_URL="${TEST_DATABASE_URL:-postgres://spendly:spendly@localhost:55432/spendly_test?sslmode=disable}"
go test ./internal/postgres -v
