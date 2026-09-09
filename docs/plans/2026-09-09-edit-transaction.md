# Transaction Editing Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Add editable and deletable quick transactions from both transaction entry points.

**Architecture:** Reuse `AddExpenseView` as a mode-driven transaction form. Keep persistence in an observable form model and propagate successful mutations through callbacks so existing screen models refresh their repository-backed data.

**Tech Stack:** Swift, SwiftUI, Observation, XCTest, `PurchaseRepository`.

---

### Task 1: Define edit-form domain behavior

**Files:**
- Modify: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`

1. Add failing tests proving that a quick `Purchase` pre-fills merchant, category, amount, and date.
2. Run the targeted XCTest suite and confirm the new tests fail because edit conversion is absent.
3. Add minimal draft initialization and updated-purchase construction that preserves identity, ownership, currency, and version while replacing editable fields.
4. Run the targeted suite and confirm it passes.

### Task 2: Implement update and delete model operations

**Files:**
- Modify: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`

1. Add failing tests for `update(_:from:)` and `delete(_:)`, including expected-version arguments and failure reporting.
2. Run the targeted suite and verify the expected failures.
3. Implement mutually exclusive loading state and repository calls in the form model.
4. Re-run the targeted suite and verify all tests pass.

### Task 3: Add edit mode to the shared form

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`

1. Add explicit create/edit configuration and initialize form state from it.
2. In edit mode, render the edit title and destructive bottom button.
3. Present a confirmation alert before deletion.
4. Route the checkmark to create or update and close only after successful persistence.
5. Keep the form open with an action-specific failure message when persistence fails.

### Task 4: Wire both transaction entry points

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`
- Modify: `ios/Spendly/Features/Expenses/AllTransactionsView.swift`
- Modify: `ios/Spendly/Features/Expenses/ExpensesHomeView.swift`
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`
- Modify: `ios/SpendlyTests/Features/AllTransactionsModelTests.swift`

1. Add failing model tests for retaining the source purchase and replacing/removing a mutated purchase in the full list.
2. Run the affected suites and verify the expected failures.
3. Make dashboard and complete-list rows accessible buttons that select their source purchase.
4. Present edit mode from both screens and propagate successful update/delete callbacks.
5. Refresh dashboard recent transactions and summary after either mutation.
6. Run affected test suites and verify they pass.

### Task 5: Final verification

**Files:**
- Review all modified files above.

1. Run the full iOS test target.
2. Build the application target for an available simulator destination.
3. Review `git diff` and `git status` for accidental or unrelated changes.
4. Report exact verification results and any remaining limitation.
