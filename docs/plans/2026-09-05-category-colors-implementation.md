# Category Colors Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add four approved default expense categories and give every category a distinct icon tint with a matching soft background.

**Architecture:** Keep category presentation metadata on `AddExpenseCategory`, where the picker and future category displays can reuse it. Render the picker icon using the same 42-point tinted container treatment as the dashboard.

**Tech Stack:** SwiftUI, XCTest, SF Symbols

---

### Task 1: Define and verify category styles

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Test: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`

1. Add tests for the complete ordered default-category list, unique tint values, and the neutral user-category style.
2. Run the focused tests and confirm they fail.
3. Add the approved categories, symbols, and tint values to `AddExpenseCategory`.
4. Render each icon in a 42-point rounded container using its tint at 12% opacity.
5. Run the focused tests, then review the diff for unrelated changes.
