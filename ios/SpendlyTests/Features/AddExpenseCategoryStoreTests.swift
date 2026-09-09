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

    func testDraftBuildsQuickPurchaseDraftForPersonalContext() throws {
        let ownerID = UserID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!)
        let spentAt = Date(timeIntervalSince1970: 1_800_000_000)
        let expectedLocalDate = AddExpenseDraft.localDate(from: spentAt)
        var draft = AddExpenseDraft()
        draft.amountText = "1 250,75"
        draft.merchant = "  Ozon Fresh  "
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")
        draft.spentAt = spentAt

        let purchaseDraft = try draft.purchaseDraft(in: .personal(ownerID))

        XCTAssertEqual(purchaseDraft.ownerID, ownerID)
        XCTAssertNil(purchaseDraft.groupID)
        XCTAssertEqual(purchaseDraft.merchant, "Ozon Fresh")
        XCTAssertEqual(purchaseDraft.spentAt, spentAt)
        XCTAssertEqual(purchaseDraft.localDate, expectedLocalDate)
        XCTAssertEqual(purchaseDraft.timeZone, TimeZone.current.identifier)
        guard case let .quick(category, amount) = purchaseDraft.kind else {
            return XCTFail("Expected quick purchase draft")
        }
        XCTAssertEqual(category, "Продукты")
        XCTAssertEqual(amount.minorUnits, 125_075)
        XCTAssertEqual(amount.currencyCode, "RUB")
    }

    func testDraftLocalDateUsesLocalCalendarDayInsteadOfUTCInstant() throws {
        let ownerID = UserID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000103")!)
        var moscowCalendar = Calendar(identifier: .gregorian)
        moscowCalendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let spentAt = moscowCalendar.date(
            from: DateComponents(year: 2026, month: 9, day: 8, hour: 0, minute: 35)
        )!
        var utcCalendar = Calendar(identifier: .gregorian)
        utcCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let expectedLocalDate = utcCalendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!
        var draft = AddExpenseDraft()
        draft.amountText = "790"
        draft.merchant = "Озон"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")
        draft.spentAt = spentAt

        let purchaseDraft = try draft.purchaseDraft(
            in: .personal(ownerID),
            calendar: moscowCalendar,
            timeZone: moscowCalendar.timeZone
        )

        XCTAssertEqual(purchaseDraft.spentAt, spentAt)
        XCTAssertEqual(purchaseDraft.localDate, expectedLocalDate)
        XCTAssertEqual(purchaseDraft.timeZone, "Europe/Moscow")
    }

    func testDraftPrefillsEditableFieldsFromQuickPurchase() throws {
        let purchase = try makePurchase(
            merchant: "Ozon Fresh",
            category: "Продукты",
            amountMinorUnits: 125_075,
            version: 4
        )

        let draft = try AddExpenseDraft(purchase: purchase)

        XCTAssertEqual(draft.merchant, "Ozon Fresh")
        XCTAssertEqual(draft.selectedCategory?.name, "Продукты")
        XCTAssertEqual(draft.amountText, "1 250,75")
        XCTAssertEqual(draft.spentAt, purchase.spentAt)
    }

    func testPrefilledDraftCannotSubmitUntilNormalizedValueChanges() throws {
        let purchase = try makePurchase(
            merchant: "Ozon Fresh",
            category: "Продукты",
            amountMinorUnits: 50_000,
            version: 4
        )
        var draft = try AddExpenseDraft(purchase: purchase)

        XCTAssertFalse(draft.canSubmit(comparedTo: purchase))

        draft.amountText = "500,00"
        draft.merchant = "  Ozon Fresh  "
        XCTAssertFalse(draft.canSubmit(comparedTo: purchase))

        draft.merchant = "Updated"
        XCTAssertTrue(draft.canSubmit(comparedTo: purchase))
    }

    func testDraftBuildsUpdatedPurchasePreservingIdentityAndVersion() throws {
        let purchase = try makePurchase(
            merchant: "Old",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 7
        )
        var draft = try AddExpenseDraft(purchase: purchase)
        draft.merchant = "  New merchant  "
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Транспорт")
        draft.amountText = "99,50"
        draft.spentAt = Date(timeIntervalSince1970: 1_900_000_000)

        let updated = try draft.updatedPurchase(purchase)

        XCTAssertEqual(updated.id, purchase.id)
        XCTAssertEqual(updated.ownerID, purchase.ownerID)
        XCTAssertEqual(updated.groupID, purchase.groupID)
        XCTAssertEqual(updated.version, 7)
        XCTAssertEqual(updated.merchant, "New merchant")
        XCTAssertEqual(updated.spentAt, draft.spentAt)
        guard case let .quick(category, amount) = updated.kind else {
            return XCTFail("Expected quick purchase")
        }
        XCTAssertEqual(category, "Транспорт")
        XCTAssertEqual(amount.minorUnits, 9_950)
        XCTAssertEqual(amount.currencyCode, "RUB")
    }

    func testAddExpenseModelCreatesPurchaseThroughRepository() async {
        let ownerID = UserID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000102")!)
        let idempotencyKey = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!
        let repository = AddExpenseRepositoryStub()
        var saveFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(ownerID),
            saveFeedback: { saveFeedbackCount += 1 }
        )
        var draft = AddExpenseDraft()
        draft.amountText = "500"
        draft.merchant = "Лента"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        let purchase = await model.save(draft, idempotencyKey: idempotencyKey)
        let calls = await repository.recordedCreateCalls()

        XCTAssertNotNil(purchase)
        XCTAssertNil(model.failure)
        XCTAssertEqual(calls.map(\.idempotencyKey), [idempotencyKey])
        XCTAssertEqual(calls.first?.draft.ownerID, ownerID)
        XCTAssertEqual(calls.first?.draft.merchant, "Лента")
        XCTAssertEqual(saveFeedbackCount, 1)
    }

    func testAddExpenseModelUpdatesPurchaseUsingCurrentVersion() async throws {
        let repository = AddExpenseRepositoryStub()
        let purchase = try makePurchase(
            merchant: "Old",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 5
        )
        var saveFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(purchase.ownerID),
            saveFeedback: { saveFeedbackCount += 1 }
        )
        var draft = try AddExpenseDraft(purchase: purchase)
        draft.merchant = "Updated"

        let updated = await model.update(purchase, with: draft)
        let calls = await repository.recordedUpdateCalls()

        XCTAssertEqual(updated?.merchant, "Updated")
        XCTAssertEqual(calls.map(\.expectedVersion), [5])
        XCTAssertEqual(calls.first?.purchase.id, purchase.id)
        XCTAssertNil(model.failure)
        XCTAssertEqual(saveFeedbackCount, 1)
    }

    func testAddExpenseModelDoesNotWriteUnchangedPurchase() async throws {
        let repository = AddExpenseRepositoryStub()
        let purchase = try makePurchase(
            merchant: "Market",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 5
        )
        var saveFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(purchase.ownerID),
            saveFeedback: { saveFeedbackCount += 1 }
        )
        let draft = try AddExpenseDraft(purchase: purchase)

        let updated = await model.update(purchase, with: draft)
        let calls = await repository.recordedUpdateCalls()

        XCTAssertNil(updated)
        XCTAssertTrue(calls.isEmpty)
        XCTAssertEqual(saveFeedbackCount, 0)
        XCTAssertNil(model.failure)
    }

    func testAddExpenseModelDeletesPurchaseUsingCurrentVersion() async throws {
        let repository = AddExpenseRepositoryStub()
        let purchase = try makePurchase(
            merchant: "Old",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 3
        )
        var deleteFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(purchase.ownerID),
            deleteFeedback: { deleteFeedbackCount += 1 }
        )

        let didDelete = await model.delete(purchase)
        let calls = await repository.recordedDeleteCalls()

        XCTAssertTrue(didDelete)
        XCTAssertEqual(calls.map(\.id), [purchase.id])
        XCTAssertEqual(calls.map(\.expectedVersion), [3])
        XCTAssertNil(model.failure)
        XCTAssertEqual(deleteFeedbackCount, 1)
    }

    func testAddExpenseModelStoresFailureWhenDeleteFails() async throws {
        let repository = AddExpenseRepositoryStub(deleteError: AppFailure.network)
        let purchase = try makePurchase(
            merchant: "Old",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 3
        )
        var deleteFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(purchase.ownerID),
            deleteFeedback: { deleteFeedbackCount += 1 }
        )

        let didDelete = await model.delete(purchase)

        XCTAssertFalse(didDelete)
        XCTAssertEqual(model.failure, .network)
        XCTAssertEqual(model.failureAction, .delete)
        XCTAssertFalse(model.isDeleting)
        XCTAssertEqual(deleteFeedbackCount, 0)
    }

    func testAddExpenseModelStoresFailureWhenUpdateFails() async throws {
        let repository = AddExpenseRepositoryStub(updateError: AppFailure.conflict)
        let purchase = try makePurchase(
            merchant: "Old",
            category: "Продукты",
            amountMinorUnits: 10_000,
            version: 2
        )
        let model = AddExpenseModel(repository: repository, context: .personal(purchase.ownerID))
        var draft = try AddExpenseDraft(purchase: purchase)
        draft.merchant = "Updated"

        let updated = await model.update(purchase, with: draft)

        XCTAssertNil(updated)
        XCTAssertEqual(model.failure, .conflict)
        XCTAssertFalse(model.isSaving)
    }

    func testAddExpenseModelStoresFailureWhenCreateFails() async {
        let repository = AddExpenseRepositoryStub(createError: AppFailure.network)
        var saveFeedbackCount = 0
        let model = AddExpenseModel(
            repository: repository,
            context: .personal(UserID(rawValue: UUID())),
            saveFeedback: { saveFeedbackCount += 1 }
        )
        var draft = AddExpenseDraft()
        draft.amountText = "500"
        draft.merchant = "Лента"
        draft.selectedCategory = AddExpenseCategory.defaultCategory(name: "Продукты")

        let purchase = await model.save(draft)

        XCTAssertNil(purchase)
        XCTAssertEqual(model.failure, .network)
        XCTAssertEqual(saveFeedbackCount, 0)
    }

    private func makePurchase(
        merchant: String,
        category: String,
        amountMinorUnits: Int64,
        version: Int64
    ) throws -> Purchase {
        try Purchase.quick(
            id: PurchaseID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!),
            ownerID: UserID(rawValue: UUID(uuidString: "00000000-0000-0000-0000-000000000101")!),
            groupID: nil,
            merchant: merchant,
            category: category,
            amount: Money(minorUnits: amountMinorUnits, currencyCode: "RUB"),
            spentAt: Date(timeIntervalSince1970: 1_800_000_000),
            localDate: Date(timeIntervalSince1970: 1_800_000_000),
            timeZone: "Europe/Moscow",
            version: version
        )
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

private actor AddExpenseRepositoryStub: PurchaseRepository {
    struct CreateCall: Equatable {
        let draft: PurchaseDraft
        let idempotencyKey: UUID
    }

    struct UpdateCall: Equatable {
        let purchase: Purchase
        let expectedVersion: Int64
    }

    struct DeleteCall: Equatable {
        let id: PurchaseID
        let expectedVersion: Int64
    }

    private let createError: Error?
    private let updateError: Error?
    private let deleteError: Error?
    private var createCalls: [CreateCall] = []
    private var updateCalls: [UpdateCall] = []
    private var deleteCalls: [DeleteCall] = []

    init(
        createError: Error? = nil,
        updateError: Error? = nil,
        deleteError: Error? = nil
    ) {
        self.createError = createError
        self.updateError = updateError
        self.deleteError = deleteError
    }

    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] {
        []
    }

    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        PurchasePage(purchases: [], nextCursor: nil, hasMore: false)
    }

    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase {
        createCalls.append(CreateCall(draft: draft, idempotencyKey: idempotencyKey))
        if let createError {
            throw createError
        }
        return try RepositoryMapping.optimisticPurchase(from: draft)
    }

    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase {
        updateCalls.append(UpdateCall(purchase: purchase, expectedVersion: expectedVersion))
        if let updateError {
            throw updateError
        }
        return purchase
    }

    func delete(id: PurchaseID, expectedVersion: Int64) async throws {
        deleteCalls.append(DeleteCall(id: id, expectedVersion: expectedVersion))
        if let deleteError {
            throw deleteError
        }
    }

    func recordedCreateCalls() -> [CreateCall] {
        createCalls
    }

    func recordedUpdateCalls() -> [UpdateCall] {
        updateCalls
    }

    func recordedDeleteCalls() -> [DeleteCall] {
        deleteCalls
    }
}
