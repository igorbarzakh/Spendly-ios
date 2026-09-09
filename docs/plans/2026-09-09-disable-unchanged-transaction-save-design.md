# Disable Unchanged Transaction Save Design

In edit mode, saving is available only when the valid normalized draft differs from the original quick purchase. Equality compares trimmed merchant, normalized category, minor-unit amount, and exact selected date. Formatting-only differences such as surrounding whitespace or `500` versus `500,00` are not changes.

The view uses this rule to disable and visually mute the confirmation button. `AddExpenseModel.update` repeats the same guard before calling the repository, preventing no-op writes even when invoked outside the button path.
