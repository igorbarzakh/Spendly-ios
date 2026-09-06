create index purchases_owner_spent_at_id_idx
    on purchases (owner_id, spent_at desc, id desc)
    where deleted_at is null;

create index purchases_group_spent_at_id_idx
    on purchases (group_id, spent_at desc, id desc)
    where deleted_at is null and group_id is not null;
