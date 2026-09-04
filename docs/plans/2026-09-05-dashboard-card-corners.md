# Dashboard Card Corners Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Apply a consistent 24/12 corner-radius hierarchy to dashboard cards and icon containers.

**Architecture:** Change only existing `RoundedRectangle` values in `DashboardView.swift`. Keep content shapes, spacing, and behavior aligned with each card.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Adjust card radii

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Use 24 points for the summary, add-transaction, and recent-operations cards.
2. Use 12 points for the add icon and transaction-category icon containers.

### Task 2: Verify

1. Run the full XCTest suite on `iPhone 17 Pro`.
2. Build for the same simulator destination.
3. Run `git diff --check` and inspect the focused source.
