package groups

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"github.com/igorbarzakh/spendly-ios/backend/internal/auth"
	"github.com/jackc/pgx/v5"
	"github.com/jackc/pgx/v5/pgxpool"
	"time"
)

type PostgresRepository struct {
	pool *pgxpool.Pool
	now  func() time.Time
}

func NewPostgresRepository(pool *pgxpool.Pool, now func() time.Time) *PostgresRepository {
	return &PostgresRepository{pool, now}
}
func (r *PostgresRepository) Create(ctx context.Context, owner auth.UserID, id, name string) (Group, error) {
	if owner == "" || id == "" || name == "" {
		return Group{}, ErrInvalidGroup
	}
	var g Group
	err := r.pool.QueryRow(ctx, `insert into groups(id,name,owner_id)values($1,$2,$3)returning id,name,owner_id,archived_at,created_at,updated_at`, id, name, owner).Scan(&g.ID, &g.Name, &g.OwnerID, &g.ArchivedAt, &g.CreatedAt, &g.UpdatedAt)
	return g, err
}
func (r *PostgresRepository) List(ctx context.Context, user auth.UserID) ([]Group, error) {
	rows, e := r.pool.Query(ctx, `select g.id,g.name,g.owner_id,g.archived_at,g.created_at,g.updated_at from groups g join group_members m on m.group_id=g.id where m.user_id=$1 order by g.created_at`, user)
	if e != nil {
		return nil, e
	}
	defer rows.Close()
	var out []Group
	for rows.Next() {
		var g Group
		if e = rows.Scan(&g.ID, &g.Name, &g.OwnerID, &g.ArchivedAt, &g.CreatedAt, &g.UpdatedAt); e != nil {
			return nil, e
		}
		out = append(out, g)
	}
	return out, rows.Err()
}
func (r *PostgresRepository) Archive(ctx context.Context, actor auth.UserID, id string) error {
	result, e := r.pool.Exec(ctx, `update groups set archived_at=now() where id=$1 and owner_id=$2 and archived_at is null`, id, actor)
	if e != nil {
		return e
	}
	if result.RowsAffected() == 0 {
		return ErrForbidden
	}
	return nil
}
func (r *PostgresRepository) UpdateMember(ctx context.Context, actor auth.UserID, group string, target auth.UserID, manage bool) error {
	var owner auth.UserID
	if e := r.pool.QueryRow(ctx, "select owner_id from groups where id=$1 and archived_at is null", group).Scan(&owner); errors.Is(e, pgx.ErrNoRows) {
		return ErrNotFound
	} else if e != nil {
		return e
	}
	if actor != owner {
		return ErrForbidden
	}
	if target == owner {
		return ErrOwnerImmutable
	}
	result, e := r.pool.Exec(ctx, "update group_members set can_manage_expenses=$3 where group_id=$1 and user_id=$2 and role='member'", group, target, manage)
	if e != nil {
		return e
	}
	if result.RowsAffected() == 0 {
		return ErrNotFound
	}
	return nil
}
func (r *PostgresRepository) CreateInvitation(ctx context.Context, actor auth.UserID, group string, ttl time.Duration) (Invitation, error) {
	if ttl <= 0 {
		return Invitation{}, ErrInvalidGroup
	}
	var active bool
	if e := r.pool.QueryRow(ctx, `select exists(select 1 from group_members m join groups g on g.id=m.group_id where m.group_id=$1 and m.user_id=$2 and g.archived_at is null)`, group, actor).Scan(&active); e != nil {
		return Invitation{}, e
	}
	if !active {
		var archived bool
		_ = r.pool.QueryRow(ctx, "select archived_at is not null from groups where id=$1", group).Scan(&archived)
		if archived {
			return Invitation{}, ErrGroupArchived
		}
		return Invitation{}, ErrForbidden
	}
	id, e := newID()
	if e != nil {
		return Invitation{}, e
	}
	var raw [32]byte
	if _, e = rand.Read(raw[:]); e != nil {
		return Invitation{}, e
	}
	token := base64.RawURLEncoding.EncodeToString(raw[:])
	hash := sha256.Sum256([]byte(token))
	expires := r.now().UTC().Add(ttl)
	_, e = r.pool.Exec(ctx, `insert into group_invitations(id,group_id,created_by,token_hash,expires_at)values($1,$2,$3,$4,$5)`, id, group, actor, hash[:], expires)
	return Invitation{ID: id, GroupID: group, Token: token, ExpiresAt: expires}, e
}
func (r *PostgresRepository) AcceptInvitation(ctx context.Context, user auth.UserID, token string) error {
	hash := sha256.Sum256([]byte(token))
	tx, e := r.pool.BeginTx(ctx, pgx.TxOptions{})
	if e != nil {
		return e
	}
	defer func() { _ = tx.Rollback(ctx) }()
	var id, group string
	var expires time.Time
	var accepted, revoked *time.Time
	e = tx.QueryRow(ctx, `select id,group_id,expires_at,accepted_at,revoked_at from group_invitations where token_hash=$1 for update`, hash[:]).Scan(&id, &group, &expires, &accepted, &revoked)
	if errors.Is(e, pgx.ErrNoRows) || accepted != nil || revoked != nil || !expires.After(r.now()) {
		return ErrInvitationUnavailable
	}
	if e != nil {
		return e
	}
	var archived bool
	if e = tx.QueryRow(ctx, "select archived_at is not null from groups where id=$1", group).Scan(&archived); e != nil || archived {
		return ErrInvitationUnavailable
	}
	if _, e = tx.Exec(ctx, `insert into group_members(group_id,user_id,role)values($1,$2,'member')`, group, user); e != nil {
		return ErrInvitationUnavailable
	}
	if _, e = tx.Exec(ctx, "update group_invitations set accepted_at=$2 where id=$1", id, r.now().UTC()); e != nil {
		return e
	}
	return tx.Commit(ctx)
}
func (r *PostgresRepository) RevokeInvitation(ctx context.Context, actor auth.UserID, group, id string) error {
	result, e := r.pool.Exec(ctx, `update group_invitations i set revoked_at=now() from groups g where i.id=$1 and i.group_id=$2 and g.id=i.group_id and (i.created_by=$3 or g.owner_id=$3) and i.accepted_at is null`, id, group, actor)
	if e != nil {
		return e
	}
	if result.RowsAffected() == 0 {
		return ErrForbidden
	}
	return nil
}
func newID() (string, error) {
	var b [16]byte
	if _, e := rand.Read(b[:]); e != nil {
		return "", e
	}
	b[6] = (b[6] & 15) | 64
	b[8] = (b[8] & 63) | 128
	return stringUUID(b), nil
}
func stringUUID(b [16]byte) string {
	const h = "0123456789abcdef"
	out := make([]byte, 36)
	j := 0
	for i, v := range b {
		if i == 4 || i == 6 || i == 8 || i == 10 {
			out[j] = '-'
			j++
		}
		out[j] = h[v>>4]
		out[j+1] = h[v&15]
		j += 2
	}
	return string(out)
}
