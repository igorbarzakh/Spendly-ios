# Unified Category Presentation Design

Standard expense categories must have the same title, SF Symbol, and tint everywhere in the app. The design-system layer owns one catalog of standard category presentations. Add Expense builds its standard category list from that catalog, while Dashboard resolves persisted category names through the same catalog. Unknown names use the neutral custom-category presentation.

This removes the duplicate switches that allowed Dashboard to recognize only five of the thirteen standard categories. Matching remains whitespace-, case-, and diacritic-insensitive, and the existing `Кафе и рестораны` alias continues to resolve to `Кафе`.

Regression tests compare every standard Add Expense category with Dashboard presentation and verify that an unknown user category remains neutral.
