package groups

import (
	"context"
	"errors"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres"
	"github.com/igorbarzakh/spendly-ios/backend/internal/postgres/testutil"
	"github.com/igorbarzakh/spendly-ios/backend/migrations"
	"github.com/jackc/pgx/v5/pgxpool"
	"testing"
	"time"
)

func TestCreateAddsOwnerMembershipAndProtectsOwner(t *testing.T) {
	pool := groupTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	member := auth.UserID("22222222-2222-4222-8222-222222222222")
	insertGroupUser(t, pool, owner)
	insertGroupUser(t, pool, member)
	repo := NewPostgresRepository(pool, time.Now)
	group, err := repo.Create(context.Background(), owner, "33333333-3333-4333-8333-333333333333", "Family")
	if err != nil {
		t.Fatal(err)
	}
	if group.OwnerID != owner {
		t.Fatal("owner mismatch")
	}
	var role string
	var manage bool
	if err = pool.QueryRow(context.Background(), "select role,can_manage_expenses from group_members where group_id=$1 and user_id=$2", group.ID, owner).Scan(&role, &manage); err != nil {
		t.Fatal(err)
	}
	if role != "owner" || !manage {
		t.Fatalf("invalid owner membership %s %t", role, manage)
	}
	if err = repo.UpdateMember(context.Background(), owner, group.ID, owner, false); !errors.Is(err, ErrOwnerImmutable) {
		t.Fatalf("expected immutable owner, got %v", err)
	}
}

func TestInvitationIsHashedSingleUseAndRequiresActiveGroup(t *testing.T) {
	pool := groupTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	member := auth.UserID("22222222-2222-4222-8222-222222222222")
	other := auth.UserID("44444444-4444-4444-8444-444444444444")
	for _, id := range []auth.UserID{owner, member, other} {
		insertGroupUser(t, pool, id)
	}
	repo := NewPostgresRepository(pool, time.Now)
	group, _ := repo.Create(context.Background(), owner, "33333333-3333-4333-8333-333333333333", "Family")
	invite, err := repo.CreateInvitation(context.Background(), owner, group.ID, time.Hour)
	if err != nil {
		t.Fatal(err)
	}
	var rawStored bool
	if err = pool.QueryRow(context.Background(), "select exists(select 1 from group_invitations where token_hash=convert_to($1,'UTF8'))", invite.Token).Scan(&rawStored); err != nil {
		t.Fatal(err)
	}
	if rawStored {
		t.Fatal("raw invitation stored")
	}
	if err = repo.AcceptInvitation(context.Background(), member, invite.Token); err != nil {
		t.Fatal(err)
	}
	if err = repo.AcceptInvitation(context.Background(), other, invite.Token); !errors.Is(err, ErrInvitationUnavailable) {
		t.Fatalf("expected single-use rejection, got %v", err)
	}
	if err = repo.Archive(context.Background(), owner, group.ID); err != nil {
		t.Fatal(err)
	}
	if _, err = repo.CreateInvitation(context.Background(), owner, group.ID, time.Hour); !errors.Is(err, ErrGroupArchived) {
		t.Fatalf("expected archived rejection, got %v", err)
	}
}

func TestOnlyOwnerCanManageMembers(t *testing.T) {
	pool := groupTestDB(t)
	owner := auth.UserID("11111111-1111-4111-8111-111111111111")
	member := auth.UserID("22222222-2222-4222-8222-222222222222")
	for _, id := range []auth.UserID{owner, member} {
		insertGroupUser(t, pool, id)
	}
	repo := NewPostgresRepository(pool, time.Now)
	group, _ := repo.Create(context.Background(), owner, "33333333-3333-4333-8333-333333333333", "Family")
	if _, err := pool.Exec(context.Background(), "insert into group_members(group_id,user_id,role) values($1,$2,'member')", group.ID, member); err != nil {
		t.Fatal(err)
	}
	if err := repo.UpdateMember(context.Background(), member, group.ID, member, true); !errors.Is(err, ErrForbidden) {
		t.Fatalf("expected forbidden, got %v", err)
	}
}

func groupTestDB(t *testing.T) *pgxpool.Pool {
	t.Helper()
	pool := testutil.EmptyPool(t)
	if err := postgres.Up(context.Background(), pool, migrations.Files); err != nil {
		t.Fatal(err)
	}
	return pool
}
func insertGroupUser(t *testing.T, p *pgxpool.Pool, id auth.UserID) {
	t.Helper()
	if _, e := p.Exec(context.Background(), "insert into users(id)values($1)", id); e != nil {
		t.Fatal(e)
	}
	if _, e := p.Exec(context.Background(), "insert into profiles(id)values($1)", id); e != nil {
		t.Fatal(e)
	}
}
