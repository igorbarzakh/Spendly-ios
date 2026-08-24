# Spendly data model

PostgreSQL is the server source of truth. SwiftData will cache normalized responses and pending mutations, but it does not define financial or permission rules.

## Identity and ownership

- `profiles.id` is the authenticated `auth.users.id`.
- `groups.owner_id` identifies the immutable owner for the first release.
- Creating a group automatically creates exactly one `group_members` row with role `owner` and expense-management permission.
- A grouped purchase has a composite foreign key to `(group_id, owner_id)` in `group_members`, so a purchase cannot be attributed to a non-member.

## Purchases

- IDs are client-generated UUIDs so offline mutations retain stable identity.
- `amount_minor` values are `bigint`; floating-point money is not accepted.
- Quick purchases require a positive amount and category.
- Detailed purchases store neither an editable amount nor a purchase-level category. Their total is derived from positive `purchase_items.amount_minor` values.
- Item positions are unique within a purchase and start at zero.
- `spent_at` is the UTC event timestamp. `local_date` and `time_zone` preserve the operation's calendar meaning.
- Updates advance the positive `version` and refresh `updated_at`. Transactional commands will use this version for optimistic concurrency.
- Deletion is represented by `deleted_at`; physical retention is handled separately.

## Invitations

`group_invitations.token_hash` stores only the unique hash of a cryptographically generated token. Expiry, acceptance, and revocation timestamps are constrained against creation time; an invitation cannot be accepted and revoked simultaneously.

## Access control

This initial migration establishes relational invariants only. RLS, grants, and their positive and negative tests are introduced in the next migration so unsafe access can first be demonstrated and then closed explicitly.

