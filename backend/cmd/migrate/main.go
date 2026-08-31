package main

import (
	"context"
	"fmt"
	"os"

	"github.com/igorbarzakh/spendly-ios/backend/internal/config"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
)

func main() {
	if len(os.Args) != 2 {
		fatal("usage: migrate up|down|status")
	}
	if err := config.LoadDotEnv(".env"); err != nil {
		fatal("load config: %v", err)
	}
	databaseURL := os.Getenv("DATABASE_URL")
	if databaseURL == "" {
		fatal("DATABASE_URL is required")
	}

	ctx := context.Background()
	pool, err := postgres.NewPool(ctx, databaseURL)
	if err != nil {
		fatal("connect to database: %v", err)
	}
	defer pool.Close()

	switch os.Args[1] {
	case "up":
		err = postgres.Up(ctx, pool, migrations.Files)
	case "down":
		err = postgres.Down(ctx, pool, migrations.Files)
	case "status":
		var statuses []postgres.MigrationStatus
		statuses, err = postgres.Status(ctx, pool)
		for _, status := range statuses {
			fmt.Printf("%04d %s\n", status.Version, status.Name)
		}
	default:
		fatal("unknown migration command %q", os.Args[1])
	}
	if err != nil {
		fatal("migration failed: %v", err)
	}
}

func fatal(format string, args ...any) {
	fmt.Fprintf(os.Stderr, format+"\n", args...)
	os.Exit(1)
}
