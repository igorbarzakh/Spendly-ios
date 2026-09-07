# All Transactions Empty State Design

**Goal:** Make the empty all-transactions screen feel intentional and give the user a direct next action.

The screen keeps its existing full-screen header. The empty area contains a compact centered group with a `receipt.fill` SF Symbol in the dashboard accent treatment, the title “Операций пока нет”, a short explanation, and a primary “Добавить транзакцию” button.

The button dismisses the all-transactions cover. `ExpensesHomeView` then presents the existing add-expense sheet, avoiding overlapping modal presentations and keeping one shared transaction-entry flow.

The layout uses the existing dashboard colors, type styles, corner radii, and spacing. Loading, error, populated-list, and pagination states remain unchanged.
