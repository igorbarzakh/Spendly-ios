# Dashboard Medium Density Design

## Goal

Bring the add-transaction card and recent-operations section to a balanced medium scale while preserving their structure and readability.

## Design

- Add card: 42-point icon container, subheadline title, footnote subtitle, 12-point internal padding, and 14-point horizontal spacing.
- Section header: headline title and footnote action.
- Transaction rows: 42-point category icons, subheadline titles and amounts, footnote metadata, 12-point horizontal spacing, and 8-point vertical padding.
- Preserve card radii, five-row limit, progress block, and safe spacing above the tab bar.

## Verification

Run the full XCTest suite and build the app for the iPhone 17 Pro simulator. Inspect the final diff for unrelated changes.
