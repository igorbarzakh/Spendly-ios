# Dashboard Medium Density Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Reduce typography, icons, and spacing in both lower dashboard blocks to a consistent medium scale.

**Architecture:** Modify only the existing SwiftUI style modifiers in `DashboardView.swift`. Keep navigation, actions, data, accessibility grouping, card shapes, and the system tab bar unchanged.

**Tech Stack:** Swift, SwiftUI, XCTest

---

### Task 1: Resize the add-transaction card

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Change the icon container from 48 to 42 points and its corner radius from 15 to 14.
2. Use subheadline semibold for the title and footnote for the subtitle.
3. Change horizontal spacing from 16 to 14 and card padding from 14 to 12.

### Task 2: Resize recent operations

**Files:**
- Modify: `ios/Spendly/Features/Dashboard/DashboardView.swift`

1. Use headline for the section title and footnote medium for the action.
2. Change row icon containers from 48 to 42 points and corner radius from 16 to 14.
3. Use subheadline semibold for row titles, footnote for metadata, and subheadline medium for amounts.
4. Change row spacing from 14 to 12 and vertical padding from 10 to 8.
5. Align separators with the resized row content.

### Task 3: Verify

1. Run the full XCTest suite on `iPhone 17 Pro`.
2. Build the app for the same simulator.
3. Run `git diff --check` and review the focused source.
