# Disable Unchanged Transaction Save Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:test-driven-development to implement this plan task-by-task.

**Goal:** Prevent unchanged transaction edits from being submitted.

**Architecture:** Put normalized change detection on `AddExpenseDraft`, reuse it for the edit confirmation button, and enforce it again in `AddExpenseModel.update` before repository access.

**Tech Stack:** Swift 6, SwiftUI, XCTest

---

1. Add failing tests for unchanged, formatting-equivalent, and changed drafts.
2. Add a failing model test proving unchanged updates do not call the repository or haptic feedback.
3. Implement normalized change detection and connect it to button state and model validation.
4. Run focused tests, the full suite, simulator build, and `git diff --check`.
