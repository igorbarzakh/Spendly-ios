alter table purchases
    add column delivery_fee_minor bigint not null default 0 check (delivery_fee_minor >= 0),
    add column discount_type text check (discount_type in ('fixed', 'percentage')),
    add column discount_value bigint check (discount_value >= 0),
    add constraint purchases_discount_payload_check check (
        (discount_type is null and discount_value is null)
        or
        (
            discount_type is not null
            and discount_value is not null
            and (discount_type <> 'percentage' or discount_value <= 100)
        )
    );

alter table purchase_items
    add column quantity bigint not null default 1 check (quantity > 0),
    add column unit_price_minor bigint not null default 0 check (unit_price_minor >= 0),
    add constraint purchase_items_price_payload_check check (
        (unit_price_minor = 0 and amount_minor > 0)
        or
        (unit_price_minor > 0 and amount_minor = quantity * unit_price_minor)
    );
