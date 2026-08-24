drop table if exists idempotency_keys;
drop table if exists purchase_items;
drop table if exists purchases;
drop table if exists group_invitations;
drop table if exists group_members;
drop table if exists groups;
drop table if exists profiles;
drop table if exists user_sessions;
drop table if exists user_identities;
drop table if exists users;

drop function if exists validate_purchase_item_parent();
drop function if exists set_purchase_updated_at_and_version();
drop function if exists validate_group_member_role();
drop function if exists add_group_owner_membership();
drop function if exists set_updated_at();
