# Dashboard Spacing Polish Design

## Goal

Improve the dashboard's visual balance without changing its structure or bottom tab bar.

## Design

- Use adaptive `systemGray5` for the unfilled monthly-limit track. It sits between the previous nearly invisible separator tint and the overly dark `systemGray4`.
- Add 8 points of vertical padding inside the recent-operations card so the first and last rows do not crowd its 28-point corners.
- Reserve a 12-point safe-area inset below the scroll content so the final card can stop above the floating system tab bar instead of visually running underneath it.
- Keep transaction row heights, card radius, transaction count, and tab bar unchanged.

## Verification

Build the app and run the full XCTest suite on the iPhone 17 Pro simulator. Review the final diff for changes outside these three layout/color adjustments.
