# Inline cart expense editor

## Goal

Make itemized carts available directly inside the expense-entry flow. A user should be able to enter several products, delivery, and a discount without moving through a chain of modal screens.

## Product model

`New purchase` has two explicit modes:

- `Single item` is the default fast path for a simple expense without a cart.
- `Cart` is an optional mode for itemized expenses.

Changing the mode must not discard entered data without confirmation. In cart mode, the total is derived from products, delivery, and discount. In single-item mode, the user enters the total directly.

## Screen structure

The purchase editor remains a single large presentation with these sections:

1. Header with dismiss and save actions.
2. Compact `Single item / Cart` mode control, with `Single item` selected by default.
3. Merchant, category, and date fields.
4. Product list in cart mode, or amount field in single-item mode.
5. Delivery and discount controls in cart mode.
6. A persistent summary showing the current total.

Cart mode does not open a separate cart composition sheet.

## Product entry

Products are represented as rows in the main screen. A collapsed row shows the product name, quantity multiplied by unit price, and row total.

Tapping `Add product` inserts one inline editor below the existing rows. Tapping an existing row expands that row into the same editor. Only one product editor is expanded at a time.

The inline editor contains:

- product name;
- quantity stepper;
- unit price;
- confirm and cancel actions.

Confirming a product collapses it into a summary row and keeps the user on the purchase screen. The `Add product` action remains immediately available for the next item. Cancelling a new empty product removes the draft row; cancelling an existing product restores its previous values.

## Totals and validation

The total updates immediately after a valid product is confirmed and after delivery or discount changes. The purchase cannot be saved while an expanded product contains invalid partial input.

A product is valid when its name is non-empty, quantity is positive, and unit price is a valid positive amount. Validation is shown next to the affected inline field without opening alerts or another screen.

Delivery is optional and non-negative. A fixed discount cannot exceed the item subtotal plus delivery; a percentage discount remains within `0...100` and applies to the item subtotal according to the existing domain behavior.

## Interaction details

- Focus moves from product name to price using the keyboard Next action.
- Confirming a row dismisses the keyboard and keeps the list position stable.
- Adding another row scrolls only enough to reveal its fields above the keyboard.
- Deleting an item uses a row action and does not navigate away.
- Category and date may continue using their existing pickers because they are independent selections, not part of the repeated cart-entry loop.

## Implementation boundaries

Reuse the existing `AddExpenseDraft`, product calculations, category picker, date picker, colors, typography, and button styles. Replace the current `CartItemsSheet` and `CartItemFormSheet` flow with inline product-row state inside `AddExpenseView`.

No receipt scanning, product catalog, autocomplete, backend schema changes, or unrelated visual redesign is included.

## Verification

Cover draft behavior with focused unit tests and add UI coverage for:

- adding several products without presenting another screen;
- editing and deleting a product inline;
- delivery and discount total calculation;
- switching between cart and amount-only modes without silent data loss;
- keyboard and layout behavior on a compact iPhone viewport.
