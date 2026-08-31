alter table purchase_items
    drop constraint if exists purchase_items_price_payload_check,
    drop column if exists unit_price_minor,
    drop column if exists quantity;

alter table purchases
    drop constraint if exists purchases_discount_payload_check,
    drop column if exists discount_value,
    drop column if exists discount_type,
    drop column if exists delivery_fee_minor;
