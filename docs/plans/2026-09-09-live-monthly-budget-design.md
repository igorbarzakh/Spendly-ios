# Live Monthly Budget Design

The budget progress is independent from the selected dashboard summary period. A dedicated observable monthly-budget model requests purchases for the current calendar month, totals their real amounts, and feeds `DashboardBudgetProgress` while the configured limit remains unchanged.

Creating a transaction refreshes the model through the existing dashboard refresh token. Update and delete events adjust both the selected-period summary and the monthly total immediately, accounting for transactions moving into or out of the current month. The progress fill animates only when its fraction changes.
