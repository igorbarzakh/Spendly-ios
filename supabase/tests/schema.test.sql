begin;

create extension if not exists pgtap with schema extensions;

select plan(29);

select has_table('public', 'profiles', 'profiles table exists');
select has_table('public', 'groups', 'groups table exists');
select has_table('public', 'group_members', 'group_members table exists');
select has_table('public', 'group_invitations', 'group_invitations table exists');
select has_table('public', 'purchases', 'purchases table exists');
select has_table('public', 'purchase_items', 'purchase_items table exists');

select has_pk('public', 'profiles', 'profiles has a primary key');
select has_pk('public', 'groups', 'groups has a primary key');
select has_pk('public', 'group_members', 'group_members has a primary key');
select has_pk('public', 'group_invitations', 'group_invitations has a primary key');
select has_pk('public', 'purchases', 'purchases has a primary key');
select has_pk('public', 'purchase_items', 'purchase_items has a primary key');

select col_type_is('public', 'purchases', 'amount_minor', 'bigint', 'quick amount uses bigint');
select col_type_is('public', 'purchase_items', 'amount_minor', 'bigint', 'item amount uses bigint');
select col_type_is('public', 'purchases', 'version', 'bigint', 'purchase version uses bigint');
select col_not_null('public', 'purchases', 'version', 'purchase version is required');

select has_index('public', 'purchases', 'purchases_owner_local_date_idx', 'owner/date index exists');
select has_index('public', 'purchases', 'purchases_group_local_date_idx', 'group/date index exists');
select has_index('public', 'purchases', 'purchases_updated_at_idx', 'updated_at index exists');

select has_check('public', 'purchases', 'purchase invariants are constrained');
select has_check('public', 'purchase_items', 'purchase item invariants are constrained');
select has_trigger('public', 'groups', 'groups_add_owner_membership', 'group owner membership trigger exists');
select has_trigger('public', 'purchases', 'purchases_set_updated_at_and_version', 'purchase version trigger exists');

insert into auth.users (id)
values
    ('00000000-0000-0000-0000-000000000001'),
    ('00000000-0000-0000-0000-000000000002');

insert into public.groups (id, name, owner_id)
values (
    '10000000-0000-0000-0000-000000000001',
    'Test group',
    '00000000-0000-0000-0000-000000000001'
);

select is(
    (
        select count(*)::bigint
        from public.group_members
        where group_id = '10000000-0000-0000-0000-000000000001'
          and user_id = '00000000-0000-0000-0000-000000000001'
          and role = 'owner'
    ),
    1::bigint,
    'creating a group creates its owner membership'
);

select throws_ok(
    $$
        insert into public.purchases (
            id, owner_id, kind, merchant, currency_code, spent_at, local_date, time_zone
        ) values (
            '20000000-0000-0000-0000-000000000001',
            '00000000-0000-0000-0000-000000000001',
            'invalid', 'Merchant', 'RUB', now(), current_date, 'Europe/Moscow'
        )
    $$,
    '23514',
    null,
    'purchase kind is constrained'
);

select throws_ok(
    $$
        insert into public.purchases (
            id, owner_id, kind, merchant, category, amount_minor,
            currency_code, spent_at, local_date, time_zone
        ) values (
            '20000000-0000-0000-0000-000000000002',
            '00000000-0000-0000-0000-000000000001',
            'quick', 'Merchant', 'Other', -1,
            'RUB', now(), current_date, 'Europe/Moscow'
        )
    $$,
    '23514',
    null,
    'quick amount must be positive'
);

select throws_ok(
    $$
        insert into public.purchases (
            id, owner_id, kind, merchant, category, amount_minor,
            currency_code, spent_at, local_date, time_zone
        ) values (
            '20000000-0000-0000-0000-000000000003',
            '00000000-0000-0000-0000-000000000001',
            'quick', 'Merchant', 'Other', 100,
            'rub', now(), current_date, 'Europe/Moscow'
        )
    $$,
    '23514',
    null,
    'currency code must be uppercase ISO 4217 format'
);

insert into public.purchases (
    id, owner_id, group_id, kind, merchant,
    currency_code, spent_at, local_date, time_zone
) values (
    '20000000-0000-0000-0000-000000000004',
    '00000000-0000-0000-0000-000000000001',
    '10000000-0000-0000-0000-000000000001',
    'detailed', 'Merchant', 'RUB', now(), current_date, 'Europe/Moscow'
);

insert into public.purchase_items (
    id, purchase_id, position, name, category, amount_minor
) values (
    '30000000-0000-0000-0000-000000000001',
    '20000000-0000-0000-0000-000000000004',
    0, 'Item', 'Other', 100
);

select throws_ok(
    $$
        insert into public.purchase_items (
            id, purchase_id, position, name, category, amount_minor
        ) values (
            '30000000-0000-0000-0000-000000000002',
            '20000000-0000-0000-0000-000000000004',
            0, 'Another item', 'Other', 100
        )
    $$,
    '23505',
    null,
    'item position is unique within a purchase'
);

select throws_ok(
    $$
        insert into public.purchases (
            id, owner_id, group_id, kind, merchant, category, amount_minor,
            currency_code, spent_at, local_date, time_zone
        ) values (
            '20000000-0000-0000-0000-000000000005',
            '00000000-0000-0000-0000-000000000002',
            '10000000-0000-0000-0000-000000000001',
            'quick', 'Merchant', 'Other', 100,
            'RUB', now(), current_date, 'Europe/Moscow'
        )
    $$,
    '23503',
    null,
    'group purchase owner must be a group member'
);

select * from finish();
rollback;

