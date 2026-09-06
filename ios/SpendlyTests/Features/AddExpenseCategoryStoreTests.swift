import XCTest
@testable import Spendly

@MainActor
final class AddExpenseCategoryStoreTests: XCTestCase {
    func testDefaultCategoriesHaveCompleteOrderedListAndUniqueColors() {
        let categories = AddExpenseCategoryStore.defaultCategories

        XCTAssertEqual(categories.map(\.name), [
            "Продукты", "Транспорт", "Кафе", "Развлечения", "Дом",
            "Здоровье", "Подарки", "Подписки", "Одежда",
            "Счета и услуги", "Образование", "Путешествия", "Красота"
        ])
        XCTAssertEqual(Set(categories.map(\.tintHex)).count, categories.count)
        XCTAssertTrue(categories.allSatisfy { !$0.symbolName.isEmpty })
    }

    func testUserCreatedCategoryUsesNeutralStyle() {
        let category = AddExpenseCategory.userCreated(name: "Питомцы")

        XCTAssertEqual(category.symbolName, "tag.fill")
        XCTAssertEqual(category.tintHex, 0x71717A)
    }

    func testSingleItemCanSaveWithAmountMerchantAndCategory() {
        var draft = AddExpenseDraft()
        draft.amountText = "500,50"
        draft.merchant = "Молоко"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        XCTAssertTrue(draft.canSave)
        XCTAssertEqual(draft.normalizedMinorUnits, 50_050)
    }

    func testSingleItemRequiresPositiveAmountMerchantAndCategory() {
        var draft = AddExpenseDraft()
        draft.merchant = "Молоко"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        for amount in ["", "0", "abc"] {
            draft.amountText = amount
            XCTAssertFalse(draft.canSave, "Invalid amount: \(amount)")
        }

        draft.amountText = "95"
        draft.merchant = "  \n "
        XCTAssertFalse(draft.canSave)

        draft.merchant = "Молоко"
        draft.selectedCategory = nil
        XCTAssertFalse(draft.canSave)
    }

    func testKeyboardLayoutAddsScrollableBottomSpaceOnlyWhenKeyboardIsVisible() {
        XCTAssertEqual(AddExpenseKeyboardLayout.bottomContentPadding(keyboardHeight: 0), 24)
        XCTAssertEqual(AddExpenseKeyboardLayout.bottomContentPadding(keyboardHeight: 336), 360)
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
