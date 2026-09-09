# Live Monthly Budget Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Drive the monthly-limit progress bar from real current-month purchases and keep it current after mutations.

**Architecture:** Add a focused observable monthly-budget model beside the selected-period summary model. Reuse the existing repository and mutation events; keep the fixed limit and animate progress-fraction changes in the view.

**Tech Stack:** Swift 6, SwiftUI Observation, XCTest

---

### Task 1: Define monthly total behavior

**Files:**
- Modify: `ios/SpendlyTests/Features/DashboardModelsTests.swift`
- Modify: `ios/Spendly/Features/Dashboard/DashboardModels.swift`

1. Add failing tests for loading the current calendar month.
2. Add failing tests for update and deletion adjustments, including movement across month boundaries.
3. Implement `DashboardMonthlyBudgetModel` minimally and make the tests pass.

### Task 2: Connect Dashboard

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Initialize the monthly model from the existing repository and context.
2. Load it on dashboard refresh and update it from mutation events.
3. Replace the sample monthly spend with the model's real total.
4. Animate changes to the progress fraction with an ease-in-out animation.

### Task 3: Verify

1. Run focused dashboard-model tests.
2. Run the complete test suite.
3. Build the simulator target and run `git diff --check`.
