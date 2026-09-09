# Transaction Editing Design

## Goal

Allow a user to open any quick transaction from the dashboard or the complete transaction list, edit the same fields used by the add form, persist the update, or delete it after confirmation.

## Design

`AddExpenseView` becomes a shared create/edit form controlled by an explicit mode. Edit mode initializes `AddExpenseDraft` from the selected `Purchase`, changes the title, calls `PurchaseRepository.update(_:expectedVersion:)`, and adds a destructive bottom action. The destructive action presents a confirmation alert before calling `PurchaseRepository.delete(id:expectedVersion:)`.

Both transaction lists make their rows buttons and present the edit form for the selected purchase. The dashboard transaction projection retains its source `Purchase`, while the complete list already owns purchases directly. Successful update or deletion dismisses the editor and refreshes the affected list and dashboard summary through the existing refresh flow.

Only quick transactions are editable. The removed multi-item purchase workflow is not extended or recreated.

## Error handling and validation

The checkmark remains disabled until all fields are valid. Saving and deleting are mutually exclusive while a request is running. Repository failures keep the editor open and show an action-specific message so the user can retry.

## Verification

Unit tests cover draft prefill, updated purchase construction, repository update/delete calls, loading state, and failures. Existing dashboard and transaction-list tests are updated for the retained source purchase. The iOS test target and application build are run after implementation.
