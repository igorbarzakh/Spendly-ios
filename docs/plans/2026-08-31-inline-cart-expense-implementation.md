# Inline Cart Expense Editor Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Keep single-item entry as the default expense-entry flow, and make multi-product cart creation, editing, totals, and purchase saving work on one screen when cart mode is selected.

**Architecture:** Extend `AddExpenseDraft` with an explicit entry mode so cart and amount-only data can coexist without ambiguous `hasItems` behavior. Replace the two product sheets with one inline editor state owned by `AddExpenseView`; reuse the existing item, money, delivery, and discount calculations. Keep category and date sheets unchanged.

**Tech Stack:** Swift 6, SwiftUI, UIKit-backed money field, XCTest, XcodeGen.

---

### Task 1: Add an explicit expense entry mode

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Test: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`

**Step 1: Write failing draft-mode tests**

Add tests proving that amount-only mode is the default, cart mode requires at least one valid item, amount-only mode reads `amountText`, and switching modes preserves both values:

```swift
func testAddExpenseDraftDefaultsToAmountOnlyMode() {
    XCTAssertEqual(AddExpenseDraft().entryMode, .amountOnly)
}

func testAmountOnlyModeUsesManualAmountEvenWhenCartIsPreserved() {
    var draft = AddExpenseDraft()
    draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95"))
    draft.amountText = "500"
    draft.entryMode = .amountOnly

    XCTAssertEqual(draft.normalizedMinorUnits, 50_000)
    XCTAssertEqual(draft.items.count, 1)
}

func testCartModeDoesNotFallBackToManualAmountWhenCartIsEmpty() {
    var draft = AddExpenseDraft()
    draft.amountText = "500"
    draft.entryMode = .cart

    XCTAssertNil(draft.normalizedMinorUnits)
}
```

**Step 2: Run the focused tests and verify they fail**

Run:

```bash
xcodegen generate
xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator -only-testing:SpendlyTests/AddExpenseCategoryStoreTests
```

Expected: failure because `entryMode` and `AddExpenseEntryMode` do not exist.

**Step 3: Add the minimal mode model**

Add:

```swift
enum AddExpenseEntryMode: Equatable, Hashable {
    case cart
    case amountOnly
}
```

Add `var entryMode: AddExpenseEntryMode = .amountOnly` to `AddExpenseDraft`, then make `normalizedMinorUnits` switch explicitly on `entryMode`:

```swift
var normalizedMinorUnits: Int? {
    switch entryMode {
    case .cart:
        guard hasItems, let totalMinorUnits else { return nil }
        return Int(exactly: totalMinorUnits)
    case .amountOnly:
        return MoneyFormatter.minorUnits(from: amountText)
    }
}
```

Do not clear either cart or amount data when the mode changes.

**Step 4: Run the focused tests and verify they pass**

Run the command from Step 2. Expected: all `AddExpenseCategoryStoreTests` pass.

**Step 5: Commit only if explicitly requested**

Stage only the two files above and use `feat(ios): add expense entry modes`.

### Task 2: Define testable inline editor behavior

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Test: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`

**Step 1: Write failing item-editor tests**

Cover valid input, whitespace-only names, zero/invalid prices, and cancel semantics for new versus existing items. Extract only the small pure behavior needed by the view; do not introduce a view model for the whole screen.

```swift
func testCartItemFormDraftRejectsZeroPrice() {
    var form = CartItemFormDraft()
    form.name = "Молоко"
    form.unitPriceText = "0"

    XCTAssertFalse(form.canSave)
}

func testEditingItemKeepsOriginalUntilConfirmed() {
    let item = AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95")
    var form = CartItemFormDraft(item: item)
    form.name = "Кефир"

    XCTAssertEqual(item.name, "Молоко")
    XCTAssertEqual(form.item.name, "Кефир")
}
```

**Step 2: Run the focused tests and verify the new cases fail where validation is incomplete**

Use the focused test command from Task 1.

**Step 3: Tighten `CartItemFormDraft` validation**

Keep the existing draft type and require a strictly positive parsed unit price:

```swift
var canSave: Bool {
    guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          quantity > 0,
          let price = MoneyFormatter.minorUnits(from: unitPriceText)
    else { return false }
    return price > 0
}
```

**Step 4: Run focused tests and verify they pass**

Expected: all focused tests pass.

**Step 5: Commit only if explicitly requested**

Use `test(ios): define inline cart item behavior`.

### Task 3: Replace modal product entry with inline rows

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift:9-340`

**Step 1: Remove modal flow state**

Delete `isItemsSheetPresented`, `isFirstItemFlowActive`, `didSaveFirstItem`, `openItemsEntry()`, the product `.sheet` modifiers, and `AddExpenseItemsEntryDestination`.

Replace them with one optional inline form state:

```swift
@State private var itemFormDraft: CartItemFormDraft?
@FocusState private var focusedItemField: ItemField?

private enum ItemField: Hashable {
    case name
    case price
}
```

**Step 2: Add the mode control**

Place a compact segmented picker below the header:

```swift
Picker("Режим траты", selection: $draft.entryMode) {
    Text("Один товар").tag(AddExpenseEntryMode.amountOnly)
    Text("Корзина").tag(AddExpenseEntryMode.cart)
}
.pickerStyle(.segmented)
```

Show the manual amount field only in `.amountOnly`. In `.cart`, show the derived total in the persistent summary instead of a large editable amount field.

**Step 3: Render collapsed product rows directly in `AddExpenseView`**

Each row shows name, `quantity × unit price`, total, and a delete icon. Tapping its content starts editing a copy through `CartItemFormDraft(item:)`; deleting removes the item without navigation.

**Step 4: Render one inline editor**

Move the controls currently inside `CartItemFormSheet` into an inline `CartItemEditor` view bound to `CartItemFormDraft`. Use the existing white surfaces, money input, SF Symbols, and quantity control.

Confirm calls `draft.upsertItem(form.item)` and clears `itemFormDraft`. Cancel only clears the form, leaving an existing item unchanged.

**Step 5: Keep `Add product` immediately available**

When no editor is open, show a full-width `plus` row after the products. It creates `CartItemFormDraft()` and focuses `.name`. Do not automatically create another row after confirmation.

**Step 6: Compile the app**

Run:

```bash
xcodegen generate
xcodebuild build -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator
```

Expected: `BUILD SUCCEEDED` with no references to the removed sheet flow.

**Step 7: Commit only if explicitly requested**

Use `feat(ios): edit cart items inline`.

### Task 4: Integrate cart adjustments and persistent summary

**Files:**
- Modify: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`
- Test: `ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift`

**Step 1: Add failing edge-case tests**

Add coverage for fixed discounts larger than subtotal plus delivery, integer conversion overflow, and an incomplete inline item preventing save.

**Step 2: Run focused tests and verify failures**

Use the focused command from Task 1.

**Step 3: Move existing additional controls into the main cart section**

Reuse the current delivery input, discount input, fixed/percentage segmented control, and summary rows from `CartItemsSheet`. Keep them below the product list and remove `CartItemsSheet` after all behavior is represented inline.

**Step 4: Add the persistent total area**

Use a bottom safe-area inset so the total and save action remain visible while the list scrolls:

```swift
.safeAreaInset(edge: .bottom) {
    cartTotalBar
}
```

The bar shows the derived total in cart mode and the manual amount in amount-only mode. Disable the save action while `itemFormDraft` exists or `draft.canSave` is false.

**Step 5: Implement inline validation messages**

Show concise field-level messages only after the user attempts to confirm an invalid product. Avoid alerts and new presentations.

**Step 6: Run focused tests and build**

Run:

```bash
xcodegen generate
xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator -only-testing:SpendlyTests/AddExpenseCategoryStoreTests
xcodebuild build -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator
```

Expected: tests pass and `BUILD SUCCEEDED`.

**Step 7: Commit only if explicitly requested**

Use `feat(ios): add inline cart totals and validation`.

### Task 5: Verify the complete iPhone flow

**Files:**
- Modify only if verification exposes a defect: `ios/Spendly/Features/AddExpense/AddExpenseView.swift`

**Step 1: Run the complete unit suite**

```bash
xcodegen generate
xcodebuild test -project Spendly.xcodeproj -scheme Spendly -sdk iphonesimulator
```

Expected: all tests pass.

**Step 2: Build for a compact simulator**

```bash
xcodebuild build -project Spendly.xcodeproj -scheme Spendly -destination 'platform=iOS Simulator,name=iPhone 17'
```

Expected: `BUILD SUCCEEDED`.

**Step 3: Manually verify the interaction**

On a compact iPhone simulator, verify:

- the screen opens in `Amount only` / `Один товар` mode;
- three products can be added without presenting another screen;
- editing and cancelling preserve the original item;
- delete, delivery, fixed discount, and percentage discount update the total;
- the focused fields stay above the keyboard;
- long product names and large prices do not overlap;
- switching to `Amount only` preserves the cart and switching back restores it;
- save is disabled for an empty cart or incomplete product.

**Step 4: Review the final diff**

Run:

```bash
git diff --check
git diff -- ios/Spendly/Features/AddExpense/AddExpenseView.swift ios/SpendlyTests/Features/AddExpenseCategoryStoreTests.swift docs/plans/2026-08-31-inline-cart-expense-design.md docs/plans/2026-08-31-inline-cart-expense-implementation.md
```

Expected: no whitespace errors and no unrelated changes.

**Step 5: Commit only if explicitly requested**

Stage only the reviewed files and use `feat(ios): streamline itemized expense entry`.
