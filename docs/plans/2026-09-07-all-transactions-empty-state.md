# All Transactions Empty State Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add a polished empty state with a working transaction-creation action.

**Architecture:** `AllTransactionsView` renders a custom empty-state component and exposes an `onAddTransaction` callback. `ExpensesHomeView` dismisses the full-screen cover and presents its existing add-expense sheet from `onDismiss`.

**Tech Stack:** SwiftUI, iOS 17+

---

### Task 1: Build the empty state

**Files:**
- Modify: `ios/Spendly/Features/Expenses/AllTransactionsView.swift`

1. Add the transaction action callback.
2. Replace the system empty view with the approved icon, copy, and primary button.
3. Keep the empty group centered below the existing header.

### Task 2: Connect the add flow

**Files:**
- Modify: `ios/Spendly/Features/Expenses/ExpensesHomeView.swift`

1. Record that the add sheet should open after the full-screen cover closes.
2. Dismiss the transactions cover from the callback.
3. Present the existing add-expense sheet from the cover's `onDismiss` callback.

### Task 3: Verify

1. Build the iOS application.
2. Run the full iOS test suite.
3. Run `git diff --check` and review the focused diff.
