# Unified Category Presentation Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Restore the correct icon and tint for every standard category on Dashboard.

**Architecture:** Put category presentation metadata in the design system and consume it from both Add Expense and Dashboard. Keep unknown categories on the existing neutral custom style.

**Tech Stack:** Swift 6, SwiftUI, XCTest

---

### Task 1: Lock the regression down

**Files:**
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`

1. Add a test that maps every standard Add Expense category into `DashboardCategory` and compares its symbol.
2. Run the focused test and confirm that categories such as `Дом` and `Здоровье` fail.

### Task 2: Introduce the shared presentation catalog

**Files:**
- Modify: `ios/Spendly/Core/DesignSystem/AppColor.swift`
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Define the complete standard category catalog with names, symbols, and tint hex values.
2. Build Add Expense defaults from the catalog.
3. Make Dashboard resolve symbols and tint values from the same catalog.
4. Preserve the neutral `tag.fill` presentation for unknown categories.

### Task 3: Verify

1. Run the focused regression test.
2. Run the complete test suite.
3. Build the iOS Simulator target and run `git diff --check`.
