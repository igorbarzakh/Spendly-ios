# Dashboard Spacing Polish Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Balance the progress-track contrast and keep the recent-operations card comfortably inside its rounded edges and above the bottom tab bar.

**Architecture:** Adjust the existing dashboard design token and SwiftUI layout modifiers only. Preserve the screen hierarchy, data flow, transaction rows, and system `TabView`.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Balance the progress track

**Files:**
- Modify: `ios/Spendly/Core/DesignSystem/AppColor.swift`

1. Change `dashboardProgressTrack` from adaptive `systemGray4` to adaptive `systemGray5`.

### Task 2: Improve recent-operations spacing

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Add 8 points of vertical padding inside the transaction card.
2. Add a 12-point bottom safe-area inset to the dashboard scroll view.
3. Keep the existing 28-point content bottom padding and all transaction row metrics unchanged.

### Task 3: Verify

1. Run the complete XCTest suite on `iPhone 17 Pro`.
2. Build the app for the same simulator destination.
3. Run `git diff --check` and inspect the focused diff.
