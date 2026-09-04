# Static Dashboard Limit and Five Recents Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Make the monthly limit a readable, non-editable demo metric and show exactly five recent operations.

**Architecture:** Keep the fixed demo limit with the other dashboard sample data. Expose a small snapshot method that caps recent transactions, then render that result in the SwiftUI screen. Remove the editor-only parsing and presentation state entirely.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Define the dashboard behavior

**Files:**
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`

1. Add failing tests asserting a fixed `100 000 ₽` sample limit and a five-item recent transaction slice.
2. Run the focused dashboard tests and confirm they fail because the new API is absent.
3. Add `DashboardSamples.currentMonthLimitMinorUnits` and `DashboardSnapshot.recentTransactions(limit:)`.
4. Run the focused dashboard tests and confirm they pass.

### Task 2: Simplify the SwiftUI screen

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Remove `@AppStorage`, editor state, the edit sheet, the limit button, the pencil, and `DashboardLimitEditor`.
2. Render the fixed sample limit directly.
3. Render only `snapshot.recentTransactions(limit: 5)` and calculate separators from that collection.
4. Change the remaining amount to a semantic primary label using a readable footnote weight.

### Task 3: Verify

**Files:**
- Review all modified dashboard files and the final Git diff.

1. Run the full test suite on an available iPhone simulator.
2. Build the app for the same simulator destination.
3. Confirm no editor code or pencil symbol remains in the dashboard implementation.
