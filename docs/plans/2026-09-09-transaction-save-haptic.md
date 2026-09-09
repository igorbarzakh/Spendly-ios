# Transaction Save Haptic Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Play gentle save haptics after transaction creation/update and distinct feedback after deletion.

**Architecture:** Inject save- and delete-feedback closures into the add-expense model and invoke them only after their corresponding repository mutation succeeds. Use native impact feedback generators in the live view.

**Tech Stack:** Swift 6, SwiftUI, UIKit, XCTest

---

### Task 1: Specify feedback timing

1. Extend create/update/delete model tests with injected counters.
2. Verify the tests fail before the feedback dependency exists.
3. Add a failure-path assertion proving no feedback occurs.

### Task 2: Implement live feedback

1. Add injectable save and delete feedback dependencies to `AddExpenseModel`.
2. Invoke each only after its matching operation succeeds.
3. Supply a reduced-intensity soft impact for save and a medium impact for delete from both Add Expense view initializers.

### Task 3: Verify

1. Run focused add-expense tests.
2. Run the complete test suite.
3. Build the simulator target and run `git diff --check`.
