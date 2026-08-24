package postgres

import (
	"context"
	"fmt"
	"io/fs"
	"sort"
	"strconv"
	"strings"

	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
)

const migrationLockID int64 = 7_052_363_195

type MigrationStatus struct {
	Version int64
	Name    string
}

type migration struct {
	version int64
	name    string
	up      string
	down    string
}

func Up(ctx context.Context, pool *pgxpool.Pool, files fs.FS) error {
	migrations, err := readMigrations(files)
	if err != nil {
		return err
	}

	return withMigrationTransaction(ctx, pool, func(tx pgx.Tx) error {
		if err := ensureMigrationTable(ctx, tx); err != nil {
			return err
		}
		for _, migration := range migrations {
			var applied bool
			if err := tx.QueryRow(ctx, "select exists(select 1 from schema_migrations where version = $1)", migration.version).Scan(&applied); err != nil {
				return err
			}
			if applied {
				continue
			}
			if _, err := tx.Exec(ctx, migration.up); err != nil {
				return fmt.Errorf("apply migration %04d: %w", migration.version, err)
			}
			if _, err := tx.Exec(ctx, "insert into schema_migrations(version, name) values ($1, $2)", migration.version, migration.name); err != nil {
				return err
			}
		}
		return nil
	})
}

func Down(ctx context.Context, pool *pgxpool.Pool, files fs.FS) error {
	migrations, err := readMigrations(files)
	if err != nil {
		return err
	}
	byVersion := make(map[int64]migration, len(migrations))
	for _, migration := range migrations {
		byVersion[migration.version] = migration
	}

	return withMigrationTransaction(ctx, pool, func(tx pgx.Tx) error {
		if err := ensureMigrationTable(ctx, tx); err != nil {
			return err
		}
		var version int64
		err := tx.QueryRow(ctx, "select version from schema_migrations order by version desc limit 1").Scan(&version)
		if err == pgx.ErrNoRows {
			return nil
		}
		if err != nil {
			return err
		}
		migration, exists := byVersion[version]
		if !exists {
			return fmt.Errorf("down migration %04d is missing", version)
		}
		if _, err := tx.Exec(ctx, migration.down); err != nil {
			return fmt.Errorf("revert migration %04d: %w", version, err)
		}
		_, err = tx.Exec(ctx, "delete from schema_migrations where version = $1", version)
		return err
	})
}

func Status(ctx context.Context, pool *pgxpool.Pool) ([]MigrationStatus, error) {
	if _, err := pool.Exec(ctx, `
		create table if not exists schema_migrations (
			version bigint primary key,
			name text not null,
			applied_at timestamptz not null default now()
		)
	`); err != nil {
		return nil, err
	}
	rows, err := pool.Query(ctx, "select version, name from schema_migrations order by version")
	if err != nil {
		return nil, err
	}
	defer rows.Close()

	statuses := make([]MigrationStatus, 0)
	for rows.Next() {
		var status MigrationStatus
		if err := rows.Scan(&status.Version, &status.Name); err != nil {
			return nil, err
		}
		statuses = append(statuses, status)
	}
	return statuses, rows.Err()
}

func withMigrationTransaction(ctx context.Context, pool *pgxpool.Pool, run func(pgx.Tx) error) error {
	tx, err := pool.BeginTx(ctx, pgx.TxOptions{})
	if err != nil {
		return err
	}
	defer func() { _ = tx.Rollback(ctx) }()

	if _, err := tx.Exec(ctx, "select pg_advisory_xact_lock($1)", migrationLockID); err != nil {
		return err
	}
	if err := run(tx); err != nil {
		return err
	}
	return tx.Commit(ctx)
}

func ensureMigrationTable(ctx context.Context, tx pgx.Tx) error {
	_, err := tx.Exec(ctx, `
		create table if not exists schema_migrations (
			version bigint primary key,
			name text not null,
			applied_at timestamptz not null default now()
		)
	`)
	return err
}

func readMigrations(files fs.FS) ([]migration, error) {
	entries, err := fs.ReadDir(files, ".")
	if err != nil {
		return nil, err
	}

	byVersion := make(map[int64]*migration)
	for _, entry := range entries {
		if entry.IsDir() || (!strings.HasSuffix(entry.Name(), ".up.sql") && !strings.HasSuffix(entry.Name(), ".down.sql")) {
			continue
		}
		parts := strings.SplitN(entry.Name(), "_", 2)
		if len(parts) != 2 {
			return nil, fmt.Errorf("invalid migration name %q", entry.Name())
		}
		version, err := strconv.ParseInt(parts[0], 10, 64)
		if err != nil {
			return nil, fmt.Errorf("invalid migration version %q: %w", parts[0], err)
		}
		content, err := fs.ReadFile(files, entry.Name())
		if err != nil {
			return nil, err
		}
		item := byVersion[version]
		if item == nil {
			item = &migration{version: version}
			byVersion[version] = item
		}
		if strings.HasSuffix(entry.Name(), ".up.sql") {
			item.name = strings.TrimSuffix(parts[1], ".up.sql")
			item.up = string(content)
		} else {
			item.down = string(content)
		}
	}

	result := make([]migration, 0, len(byVersion))
	for _, item := range byVersion {
		if item.up == "" || item.down == "" {
			return nil, fmt.Errorf("migration %04d must have up and down files", item.version)
		}
		result = append(result, *item)
	}
	sort.Slice(result, func(i, j int) bool { return result[i].version < result[j].version })
	return result, nil
}
