create extension if not exists pgcrypto;

create table users (
    id uuid primary key default gen_random_uuid(),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table user_identities (
    id uuid primary key default gen_random_uuid(),
    user_id uuid not null references users (id) on delete cascade,
    provider text not null check (provider in ('apple', 'google')),
    provider_subject text not null check (btrim(provider_subject) <> ''),
    email_at_link text,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (provider, provider_subject),
    unique (user_id, provider)
);

create table user_sessions (
    id uuid primary key default gen_random_uuid(),
    family_id uuid not null,
    user_id uuid not null references users (id) on delete cascade,
    token_hash bytea not null unique check (octet_length(token_hash) = 32),
    expires_at timestamptz not null,
    used_at timestamptz,
    revoked_at timestamptz,
    replaced_by_session_id uuid references user_sessions (id) on delete set null,
    created_at timestamptz not null default now(),
    check (expires_at > created_at),
    check (used_at is null or used_at >= created_at),
    check (revoked_at is null or revoked_at >= created_at)
);

create table profiles (
    id uuid primary key references users (id) on delete cascade,
    display_name text,
    currency_code char(3) not null default 'RUB'
        check (currency_code ~ '^[A-Z]{3}$'),
    time_zone text not null default 'Europe/Moscow'
        check (btrim(time_zone) <> ''),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table groups (
    id uuid primary key,
    name text not null check (btrim(name) <> ''),
    owner_id uuid not null references users (id) on delete restrict,
    archived_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table group_members (
    group_id uuid not null references groups (id) on delete cascade,
    user_id uuid not null references users (id) on delete cascade,
    role text not null check (role in ('owner', 'member')),
    can_manage_expenses boolean not null default false,
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id)
);

create unique index group_members_one_owner_idx
    on group_members (group_id)
    where role = 'owner';

create table group_invitations (
    id uuid primary key,
    group_id uuid not null references groups (id) on delete cascade,
    created_by uuid not null references users (id) on delete cascade,
    token_hash bytea not null unique check (octet_length(token_hash) = 32),
    expires_at timestamptz not null,
    accepted_at timestamptz,
    revoked_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    check (expires_at > created_at),
    check (accepted_at is null or accepted_at >= created_at),
    check (revoked_at is null or revoked_at >= created_at),
    check (accepted_at is null or revoked_at is null)
);

create table purchases (
    id uuid primary key,
    owner_id uuid not null references users (id) on delete restrict,
    group_id uuid references groups (id) on delete restrict,
    kind text not null check (kind in ('quick', 'detailed')),
    merchant text not null check (btrim(merchant) <> ''),
    category text,
    amount_minor bigint,
    currency_code char(3) not null check (currency_code ~ '^[A-Z]{3}$'),
    spent_at timestamptz not null,
    local_date date not null,
    time_zone text not null check (btrim(time_zone) <> ''),
    version bigint not null default 1 check (version > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    deleted_at timestamptz,
    constraint purchases_group_owner_membership_fk
        foreign key (group_id, owner_id)
        references group_members (group_id, user_id)
        on delete restrict,
    constraint purchases_kind_payload_check check (
        (
            kind = 'quick'
            and category is not null
            and btrim(category) <> ''
            and amount_minor is not null
            and amount_minor > 0
        )
        or
        (
            kind = 'detailed'
            and category is null
            and amount_minor is null
        )
    )
);

create table purchase_items (
    id uuid primary key,
    purchase_id uuid not null references purchases (id) on delete cascade,
    position integer not null check (position >= 0),
    name text not null check (btrim(name) <> ''),
    category text not null check (btrim(category) <> ''),
    amount_minor bigint not null check (amount_minor > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (purchase_id, position)
);

create table idempotency_keys (
    user_id uuid not null references users (id) on delete cascade,
    key uuid not null,
    request_hash bytea not null check (octet_length(request_hash) = 32),
    response_status integer not null check (response_status between 200 and 599),
    response_body jsonb not null,
    created_at timestamptz not null default now(),
    expires_at timestamptz not null,
    primary key (user_id, key),
    check (expires_at > created_at)
);

create index user_identities_user_id_idx on user_identities (user_id);
create index user_sessions_user_id_idx on user_sessions (user_id, created_at desc);
create index user_sessions_family_id_idx on user_sessions (family_id);
create index purchases_owner_local_date_idx
    on purchases (owner_id, local_date)
    where deleted_at is null;
create index purchases_group_local_date_idx
    on purchases (group_id, local_date)
    where group_id is not null and deleted_at is null;
create index purchases_updated_at_idx on purchases (updated_at, id);
create index purchase_items_purchase_id_idx on purchase_items (purchase_id, position);
create index group_members_user_id_idx on group_members (user_id, group_id);
create index group_invitations_group_id_idx on group_invitations (group_id);
create index idempotency_keys_expires_at_idx on idempotency_keys (expires_at);

create function set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger users_set_updated_at
before update on users
for each row execute function set_updated_at();

create trigger user_identities_set_updated_at
before update on user_identities
for each row execute function set_updated_at();

create trigger profiles_set_updated_at
before update on profiles
for each row execute function set_updated_at();

create trigger groups_set_updated_at
before update on groups
for each row execute function set_updated_at();

create trigger group_invitations_set_updated_at
before update on group_invitations
for each row execute function set_updated_at();

create trigger purchase_items_set_updated_at
before update on purchase_items
for each row execute function set_updated_at();

create function add_group_owner_membership()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    insert into public.group_members (group_id, user_id, role, can_manage_expenses)
    values (new.id, new.owner_id, 'owner', true);
    return new;
end;
$$;

create trigger groups_add_owner_membership
after insert on groups
for each row execute function add_group_owner_membership();

create function validate_group_member_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    expected_owner_id uuid;
begin
    select owner_id into expected_owner_id
    from public.groups
    where id = new.group_id;

    if new.role = 'owner' and new.user_id <> expected_owner_id then
        raise exception 'owner role must match groups.owner_id' using errcode = '23514';
    end if;
    if new.user_id = expected_owner_id and new.role <> 'owner' then
        raise exception 'group owner must retain owner role' using errcode = '23514';
    end if;
    return new;
end;
$$;

create trigger group_members_validate_role
before insert or update on group_members
for each row execute function validate_group_member_role();

create function set_purchase_updated_at_and_version()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    new.version = old.version + 1;
    return new;
end;
$$;

create trigger purchases_set_updated_at_and_version
before update on purchases
for each row execute function set_purchase_updated_at_and_version();

create function validate_purchase_item_parent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not exists (
        select 1 from public.purchases
        where id = new.purchase_id and kind = 'detailed' and deleted_at is null
    ) then
        raise exception 'purchase items require an active detailed purchase' using errcode = '23514';
    end if;
    return new;
end;
$$;

create trigger purchase_items_validate_parent
before insert or update on purchase_items
for each row execute function validate_purchase_item_parent();
