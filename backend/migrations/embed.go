package migrations

import (
	"embed"
)

// Files contains the versioned SQL used by the migration command and tests.
//
//go:embed *.sql
var Files embed.FS
