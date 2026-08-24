create extension if not exists pgcrypto with schema extensions;

create table public.profiles (
    id uuid primary key references auth.users (id) on delete cascade,
    display_name text,
    currency_code char(3) not null default 'RUB'
        check (currency_code ~ '^[A-Z]{3}$'),
    time_zone text not null default 'Europe/Moscow'
        check (btrim(time_zone) <> ''),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.groups (
    id uuid primary key,
    name text not null check (btrim(name) <> ''),
    owner_id uuid not null references auth.users (id) on delete restrict,
    archived_at timestamptz,
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now()
);

create table public.group_members (
    group_id uuid not null references public.groups (id) on delete cascade,
    user_id uuid not null references auth.users (id) on delete cascade,
    role text not null check (role in ('owner', 'member')),
    can_manage_expenses boolean not null default false,
    joined_at timestamptz not null default now(),
    primary key (group_id, user_id)
);

create unique index group_members_one_owner_idx
    on public.group_members (group_id)
    where role = 'owner';

create table public.group_invitations (
    id uuid primary key,
    group_id uuid not null references public.groups (id) on delete cascade,
    created_by uuid not null references auth.users (id) on delete cascade,
    token_hash text not null unique check (btrim(token_hash) <> ''),
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

create table public.purchases (
    id uuid primary key,
    owner_id uuid not null references auth.users (id) on delete restrict,
    group_id uuid references public.groups (id) on delete restrict,
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
        references public.group_members (group_id, user_id)
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

create table public.purchase_items (
    id uuid primary key,
    purchase_id uuid not null references public.purchases (id) on delete cascade,
    position integer not null check (position >= 0),
    name text not null check (btrim(name) <> ''),
    category text not null check (btrim(category) <> ''),
    amount_minor bigint not null check (amount_minor > 0),
    created_at timestamptz not null default now(),
    updated_at timestamptz not null default now(),
    unique (purchase_id, position)
);

create index purchases_owner_local_date_idx
    on public.purchases (owner_id, local_date)
    where deleted_at is null;

create index purchases_group_local_date_idx
    on public.purchases (group_id, local_date)
    where group_id is not null and deleted_at is null;

create index purchases_updated_at_idx
    on public.purchases (updated_at);

create index purchase_items_purchase_id_idx
    on public.purchase_items (purchase_id, position);

create index group_members_user_id_idx
    on public.group_members (user_id, group_id);

create index group_invitations_group_id_idx
    on public.group_invitations (group_id);

create or replace function public.set_updated_at()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    new.updated_at = now();
    return new;
end;
$$;

create trigger profiles_set_updated_at
before update on public.profiles
for each row execute function public.set_updated_at();

create trigger groups_set_updated_at
before update on public.groups
for each row execute function public.set_updated_at();

create trigger group_invitations_set_updated_at
before update on public.group_invitations
for each row execute function public.set_updated_at();

create trigger purchase_items_set_updated_at
before update on public.purchase_items
for each row execute function public.set_updated_at();

create or replace function public.add_group_owner_membership()
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
after insert on public.groups
for each row execute function public.add_group_owner_membership();

create or replace function public.validate_group_member_role()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
    expected_owner_id uuid;
begin
    select owner_id
    into expected_owner_id
    from public.groups
    where id = new.group_id;

    if new.role = 'owner' and new.user_id <> expected_owner_id then
        raise exception 'owner role must match groups.owner_id'
            using errcode = '23514';
    end if;

    if new.user_id = expected_owner_id and new.role <> 'owner' then
        raise exception 'group owner must retain owner role'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger group_members_validate_role
before insert or update on public.group_members
for each row execute function public.validate_group_member_role();

create or replace function public.set_purchase_updated_at_and_version()
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
before update on public.purchases
for each row execute function public.set_purchase_updated_at_and_version();

create or replace function public.validate_purchase_item_parent()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
    if not exists (
        select 1
        from public.purchases
        where id = new.purchase_id
          and kind = 'detailed'
          and deleted_at is null
    ) then
        raise exception 'purchase items require an active detailed purchase'
            using errcode = '23514';
    end if;

    return new;
end;
$$;

create trigger purchase_items_validate_parent
before insert or update on public.purchase_items
for each row execute function public.validate_purchase_item_parent();

