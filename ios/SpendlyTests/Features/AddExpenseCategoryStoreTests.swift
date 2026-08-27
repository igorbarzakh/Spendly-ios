import XCTest
@testable import Spendly

@MainActor
final class AddExpenseCategoryStoreTests: XCTestCase {
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
