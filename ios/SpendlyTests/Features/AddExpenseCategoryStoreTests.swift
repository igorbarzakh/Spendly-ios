import XCTest
@testable import Spendly

@MainActor
final class AddExpenseCategoryStoreTests: XCTestCase {
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

    func testSwitchingEntryModesPreservesCartAndManualAmount() {
        var draft = AddExpenseDraft()
        let item = AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95")
        draft.upsertItem(item)
        draft.amountText = "500"

        draft.entryMode = .amountOnly
        XCTAssertEqual(draft.normalizedMinorUnits, 50_000)

        draft.entryMode = .cart
        XCTAssertEqual(draft.normalizedMinorUnits, 9_500)
        XCTAssertEqual(draft.amountText, "500")
        XCTAssertEqual(draft.items, [item])
    }

    func testCartItemFormDraftRejectsWhitespaceNameAndNonPositivePrice() {
        var form = CartItemFormDraft()
        form.name = "  \n "
        form.unitPriceText = "95"
        XCTAssertFalse(form.canSave)

        form.name = "Молоко"
        form.unitPriceText = "0"
        XCTAssertFalse(form.canSave)

        form.unitPriceText = "95"
        form.quantity = 0
        XCTAssertFalse(form.canSave)
    }

    func testEditingItemKeepsOriginalUntilConfirmed() {
        let item = AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95")
        var form = CartItemFormDraft(item: item)
        form.name = "Кефир"

        XCTAssertEqual(item.name, "Молоко")
        XCTAssertEqual(form.item.name, "Кефир")
        XCTAssertEqual(form.item.id, item.id)
    }

    func testOpenItemEditorDisablesExpenseSave() {
        var draft = AddExpenseDraft()
        draft.entryMode = .cart
        draft.merchant = "Магазин"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95"))

        XCTAssertTrue(draft.isSaveEnabled(hasOpenItemEditor: false))
        XCTAssertFalse(draft.isSaveEnabled(hasOpenItemEditor: true))
    }

    func testAmountOnlyModeCanSaveWithManualAmountMerchantAndCategory() {
        var draft = AddExpenseDraft()
        draft.entryMode = .amountOnly
        draft.amountText = "500"
        draft.merchant = "Магазин"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        XCTAssertTrue(draft.isSaveEnabled(hasOpenItemEditor: false))
        XCTAssertEqual(draft.normalizedMinorUnits, 50_000)
    }

    func testCartModeCanSaveOnlyWithConfirmedItemMerchantAndCategory() {
        var draft = AddExpenseDraft()
        draft.entryMode = .cart
        draft.merchant = "Магазин"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        XCTAssertFalse(draft.isSaveEnabled(hasOpenItemEditor: false))

        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95"))

        XCTAssertTrue(draft.isSaveEnabled(hasOpenItemEditor: false))
        XCTAssertFalse(draft.isSaveEnabled(hasOpenItemEditor: true))
        XCTAssertEqual(draft.normalizedMinorUnits, 9_500)
    }

    func testKeyboardLayoutAddsScrollableBottomSpaceOnlyWhenKeyboardIsVisible() {
        XCTAssertEqual(AddExpenseKeyboardLayout.bottomContentPadding(keyboardHeight: 0), 24)
        XCTAssertEqual(AddExpenseKeyboardLayout.bottomContentPadding(keyboardHeight: 336), 360)
    }

    func testAddExpenseDraftCalculatesCartTotalWithDeliveryAndFixedDiscount() {
        var draft = AddExpenseDraft()
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 2, unitPriceText: "95"))
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Хлеб", quantity: 1, unitPriceText: "120"))
        draft.deliveryFeeText = "99"
        draft.discountText = "10"
        draft.discountType = .fixed

        XCTAssertEqual(draft.itemsSubtotalMinorUnits, 31_000)
        XCTAssertEqual(draft.discountMinorUnits, 1_000)
        XCTAssertEqual(draft.totalMinorUnits, 39_900)
    }

    func testAddExpenseDraftCalculatesPercentageDiscountFromItemsOnly() {
        var draft = AddExpenseDraft()
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 2, unitPriceText: "95"))
        draft.deliveryFeeText = "99"
        draft.discountText = "10"
        draft.discountType = .percentage

        XCTAssertEqual(draft.discountMinorUnits, 1_900)
        XCTAssertEqual(draft.totalMinorUnits, 27_000)
    }

    func testFixedDiscountCannotExceedItemsSubtotalAndDelivery() {
        var draft = AddExpenseDraft()
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95"))
        draft.deliveryFeeText = "5"
        draft.discountType = .fixed
        draft.discountText = "101"

        XCTAssertNil(draft.totalMinorUnits)
        XCTAssertNil(draft.normalizedMinorUnits)
    }

    func testFixedDiscountCanUseItemsSubtotalAndDelivery() {
        var draft = AddExpenseDraft()
        draft.upsertItem(AddExpenseItemDraft(id: UUID(), name: "Молоко", quantity: 1, unitPriceText: "95"))
        draft.deliveryFeeText = "5"
        draft.discountType = .fixed
        draft.discountText = "100"

        XCTAssertEqual(draft.totalMinorUnits, 0)
    }

    func testValidatedNewCategoryNameTrimsOuterWhitespaceAndNewlines() {
        let result = AddExpenseCategoryStore.validatedNewCategoryName(
            "\n  Кафе  \n",
            existingCategories: [AddExpenseCategory.defaultCategory(name: "Продукты")]
        )

        XCTAssertEqual(result, "Кафе")
    }

    func testValidatedNewCategoryNameRejectsEmptyValue() {
        let result = AddExpenseCategoryStore.validatedNewCategoryName(
            " \n ",
            existingCategories: []
        )

        XCTAssertNil(result)
    }

    func testValidatedNewCategoryNameRejectsCaseInsensitiveDuplicate() {
        let result = AddExpenseCategoryStore.validatedNewCategoryName(
            "продукты",
            existingCategories: [AddExpenseCategory.defaultCategory(name: "Продукты")]
        )

        XCTAssertNil(result)
    }

    func testCreateCategoryReturnsUserCreatedCategoryAndStoresIt() {
        AddExpenseCategoryStore.resetUserCategories()

        let category = AddExpenseCategoryStore.createCategory(named: "  Обед  ")

        XCTAssertEqual(category?.name, "Обед")
        XCTAssertEqual(category?.kind, .userCreated)
        XCTAssertNotNil(category)
        if let category {
            XCTAssertTrue(AddExpenseCategoryStore.categories.contains(category))
        }
    }

    func testCreateCategoryRejectsDefaultCategoryDuplicate() {
        AddExpenseCategoryStore.resetUserCategories()

        let category = AddExpenseCategoryStore.createCategory(named: " продукты ")

        XCTAssertNil(category)
    }

    func testFilteredCategoriesMatchesCaseInsensitively() {
        let result = AddExpenseCategoryStore.filteredCategories(matching: "про")

        XCTAssertEqual(result.map(\.name), ["Продукты"])
    }
}
