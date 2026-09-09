import XCTest
@testable import Spendly

@MainActor
final class DashboardModelsTests: XCTestCase {
    func testDashboardUsesFixedDemoMonthlyLimit() {
        XCTAssertEqual(DashboardSamples.currentMonthLimitMinorUnits, 10_000_000)
    }

    func testRecentTransactionsAreLimitedToRequestedCount() {
        let snapshot = DashboardSamples.snapshot(for: .month)

        XCTAssertEqual(snapshot.recentTransactions(limit: 5).count, 5)
        XCTAssertEqual(
            snapshot.recentTransactions(limit: 5).map(\.id),
            Array(snapshot.transactions.prefix(5)).map(\.id)
        )
    }

    func testBudgetProgressCalculatesRemainingAmountAndFraction() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: 8_432_000,
            limitMinorUnits: 10_000_000
        )

        XCTAssertEqual(progress.fraction, 0.8432, accuracy: 0.0001)
        XCTAssertEqual(progress.remainingMinorUnits, 1_568_000)
        XCTAssertEqual(progress.overageMinorUnits, 0)
        XCTAssertFalse(progress.isOverLimit)
    }

    func testBudgetProgressCapsVisualFractionAndReportsOverage() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: 12_500_000,
            limitMinorUnits: 10_000_000
        )

        XCTAssertEqual(progress.fraction, 1)
        XCTAssertEqual(progress.remainingMinorUnits, 0)
        XCTAssertEqual(progress.overageMinorUnits, 2_500_000)
        XCTAssertTrue(progress.isOverLimit)
    }

    func testBudgetProgressNormalizesInvalidAmounts() {
        let progress = DashboardBudgetProgress(
            spentMinorUnits: -1,
            limitMinorUnits: 0
        )

        XCTAssertEqual(progress.fraction, 0)
        XCTAssertEqual(progress.remainingMinorUnits, 0)
        XCTAssertEqual(progress.overageMinorUnits, 0)
        XCTAssertFalse(progress.isOverLimit)
    }

    func testPeriodsHaveStableDisplayOrderAndTitles() {
        XCTAssertEqual(DashboardPeriod.allCases, [.day, .month, .year])
        XCTAssertEqual(DashboardPeriod.allCases.map(\.title), ["День", "Месяц", "Год"])
    }

    func testDefaultPeriodIsDay() {
        XCTAssertEqual(DashboardPeriod.defaultSelection, .day)
    }

    func testEveryPeriodProvidesCompleteSampleSnapshot() {
        for period in DashboardPeriod.allCases {
            let snapshot = DashboardSamples.snapshot(for: period)

            XCTAssertEqual(snapshot.period, period)
            XCTAssertGreaterThan(snapshot.totalMinorUnits, 0)
            XCTAssertFalse(snapshot.transactions.isEmpty)
        }
    }

    func testTransactionsUseCategorySymbolsInsteadOfMerchantArtwork() {
        for period in DashboardPeriod.allCases {
            let transactions = DashboardSamples.snapshot(for: period).transactions

            XCTAssertTrue(transactions.allSatisfy { !$0.category.symbolName.isEmpty })
        }
    }

    func testDashboardUsesSameSymbolsForEveryStandardExpenseCategory() {
        for category in AddExpenseCategoryStore.defaultCategories {
            XCTAssertEqual(
                DashboardCategory(name: category.name).symbolName,
                category.symbolName,
                "Category: \(category.name)"
            )
            XCTAssertEqual(
                DashboardCategory(name: category.name).tintHex,
                category.tintHex,
                "Category: \(category.name)"
            )
        }
    }

    func testDashboardKeepsUnknownCategoryNeutral() {
        let category = DashboardCategory(name: "Питомцы")

        XCTAssertEqual(category.title, "Питомцы")
        XCTAssertEqual(category.symbolName, ExpenseCategoryPresentation.customSymbolName)
        XCTAssertEqual(category.tintHex, ExpenseCategoryPresentation.customTintHex)
    }

    func testPeriodSummaryTitlesDescribeSelectedRange() {
        XCTAssertEqual(DashboardPeriod.day.summaryTitle, "Потрачено сегодня")
        XCTAssertEqual(DashboardPeriod.month.summaryTitle, "Потрачено в этом месяце")
        XCTAssertEqual(DashboardPeriod.year.summaryTitle, "Потрачено за год")
    }

    func testDashboardFormattingUsesRublesAndTypographicMinus() {
        XCTAssertEqual(DashboardFormatting.amount(8_432_000), "84 320 ₽")
        XCTAssertEqual(DashboardFormatting.expense(124_700), "−1 247 ₽")
    }

    func testTransactionDetailsShowItemCountOnlyForBasketPurchases() {
        let transactions = DashboardSamples.snapshot(for: .month).transactions

        XCTAssertEqual(transactions[0].detailsText, "Продукты · 5 товаров")
        XCTAssertEqual(transactions[1].detailsText, "Транспорт")
        XCTAssertEqual(transactions[4].detailsText, "Покупки · 2 товара")
    }

    func testItemCountFormattingUsesRussianPluralForms() {
        XCTAssertEqual(DashboardFormatting.itemCount(1), "1 товар")
        XCTAssertEqual(DashboardFormatting.itemCount(2), "2 товара")
        XCTAssertEqual(DashboardFormatting.itemCount(5), "5 товаров")
        XCTAssertEqual(DashboardFormatting.itemCount(11), "11 товаров")
        XCTAssertEqual(DashboardFormatting.itemCount(21), "21 товар")
    }

    func testRecentTransactionsModelLoadsFirstFivePurchases() async throws {
        let first = try purchase(
            id: "11111111-1111-4111-8111-111111111111",
            merchant: "Market",
            kind: .quick(category: "Продукты", amount: Money(minorUnits: 1_250, currencyCode: "RUB"))
        )
        let second = try purchase(
            id: "22222222-2222-4222-8222-222222222222",
            merchant: "Cafe",
            kind: .quick(category: "Кафе", amount: Money(minorUnits: 2_500, currencyCode: "RUB"))
        )
        let repository = DashboardRepositoryStub(page: PurchasePage(
            purchases: [first, second],
            nextCursor: "next",
            hasMore: true
        ))
        let model = DashboardRecentTransactionsModel(
            repository: repository,
            context: .personal(first.ownerID)
        )

        await model.load()

        XCTAssertEqual(model.transactions.map(\.id), [
            first.id.rawValue.uuidString,
            second.id.rawValue.uuidString
        ])
        XCTAssertEqual(model.transactions[0].merchant, "Market")
        XCTAssertEqual(model.transactions[0].category.title, "Продукты")
        XCTAssertEqual(model.transactions[0].amountMinorUnits, 1_250)
        XCTAssertEqual(model.transactions[0].purchase, first)
        XCTAssertNil(model.failure)
        let requests = await repository.recordedRequests()
        XCTAssertEqual(requests.map(\.cursor), [nil])
        XCTAssertEqual(requests.map(\.limit), [5])
    }

    func testRecentTransactionsModelMapsDetailedPurchaseItemCount() async throws {
        let firstItem = try PurchaseItem(
            id: PurchaseItemID(rawValue: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!),
            name: "Milk",
            category: "Продукты",
            amount: Money(minorUnits: 1_000, currencyCode: "RUB")
        )
        let secondItem = try PurchaseItem(
            id: PurchaseItemID(rawValue: UUID(uuidString: "44444444-4444-4444-8444-444444444444")!),
            name: "Bread",
            category: "Продукты",
            amount: Money(minorUnits: 500, currencyCode: "RUB")
        )
        let purchase = try purchase(
            id: "55555555-5555-4555-8555-555555555555",
            merchant: "Groceries",
            kind: .detailed(items: [firstItem, secondItem])
        )
        let model = DashboardRecentTransactionsModel(
            repository: DashboardRepositoryStub(page: PurchasePage(
                purchases: [purchase],
                nextCursor: nil,
                hasMore: false
            )),
            context: .personal(purchase.ownerID)
        )

        await model.load()

        XCTAssertEqual(model.transactions.first?.category.title, "Продукты")
        XCTAssertEqual(model.transactions.first?.itemCount, 2)
        XCTAssertEqual(model.transactions.first?.amountMinorUnits, 1_500)
    }

    func testRecentTransactionsModelStoresFailure() async throws {
        let ownerID = UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let model = DashboardRecentTransactionsModel(
            repository: DashboardRepositoryStub(error: AppFailure.unknown),
            context: .personal(ownerID)
        )

        await model.load()

        XCTAssertTrue(model.transactions.isEmpty)
        XCTAssertEqual(model.failure, .unknown)
        XCTAssertFalse(model.isLoading)
    }

    func testRecentTransactionsModelAppliesUpdateAndDeletionWithoutReloading() async throws {
        let original = try purchase(
            id: "11111111-1111-4111-8111-111111111111",
            merchant: "Old",
            kind: .quick(category: "Продукты", amount: Money(minorUnits: 1_000, currencyCode: "RUB"))
        )
        let updated = try Purchase.quick(
            id: original.id,
            ownerID: original.ownerID,
            groupID: original.groupID,
            merchant: "Updated",
            category: "Транспорт",
            amount: Money(minorUnits: 2_000, currencyCode: "RUB"),
            spentAt: original.spentAt,
            localDate: original.localDate,
            timeZone: original.timeZone,
            version: original.version
        )
        let model = DashboardRecentTransactionsModel(
            repository: DashboardRepositoryStub(page: PurchasePage(
                purchases: [original], nextCursor: nil, hasMore: false
            )),
            context: .personal(original.ownerID)
        )
        await model.load()

        model.applyUpdatedPurchase(updated)
        XCTAssertEqual(model.transactions.first?.purchase, updated)
        XCTAssertEqual(model.transactions.first?.merchant, "Updated")

        model.removeDeletedPurchase(id: updated.id)
        XCTAssertTrue(model.transactions.isEmpty)
    }

    func testRecentTransactionsModelReloadsFirstPageToReplenishDeletedRows() async throws {
        let ids = [
            "11111111-1111-4111-8111-111111111111",
            "22222222-2222-4222-8222-222222222222",
            "33333333-3333-4333-8333-333333333333",
            "44444444-4444-4444-8444-444444444444",
            "55555555-5555-4555-8555-555555555555",
            "66666666-6666-4666-8666-666666666666",
            "77777777-7777-4777-8777-777777777777"
        ]
        let purchases = try ids.enumerated().map { index, id in
            try purchase(
                id: id,
                merchant: "Market \(index)",
                kind: .quick(
                    category: "Продукты",
                    amount: Money(minorUnits: Int64(index + 1) * 100, currencyCode: "RUB")
                )
            )
        }
        let repository = DashboardRepositoryStub(pages: [
            PurchasePage(purchases: Array(purchases.prefix(5)), nextCursor: nil, hasMore: false),
            PurchasePage(purchases: Array(purchases.dropFirst(2).prefix(5)), nextCursor: nil, hasMore: false)
        ])
        let model = DashboardRecentTransactionsModel(
            repository: repository,
            context: .personal(purchases[0].ownerID)
        )
        await model.load()
        model.removeDeletedPurchase(id: purchases[0].id)
        model.removeDeletedPurchase(id: purchases[1].id)

        await model.replenishIfNeeded()

        XCTAssertEqual(model.transactions.compactMap(\.purchase), Array(purchases.dropFirst(2)))
        let requests = await repository.recordedRequests()
        XCTAssertEqual(requests.map(\.cursor), [nil, nil])
        XCTAssertEqual(requests.map(\.limit), [5, 5])
    }

    func testSummaryModelLoadsSelectedPeriodTotal() async throws {
        let ownerID = UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let purchase = try Purchase.quick(
            id: PurchaseID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
            ownerID: ownerID,
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 42_000, currencyCode: "RUB"),
            spentAt: Date(timeIntervalSince1970: 1_778_284_800),
            localDate: Date(timeIntervalSince1970: 1_778_284_800),
            timeZone: "UTC",
            version: 1
        )
        let repository = DashboardRepositoryStub(purchases: [purchase])
        let model = DashboardSummaryModel(
            repository: repository,
            context: .personal(ownerID)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 12))!

        await model.load(period: .month, now: now, calendar: calendar)

        XCTAssertEqual(model.totalMinorUnits, 42_000)
        XCTAssertNil(model.failure)
        XCTAssertFalse(model.isLoading)
        let requests = await repository.recordedPurchaseRequests()
        XCTAssertEqual(requests.map(\.context), [.personal(ownerID)])
        XCTAssertEqual(requests.first?.interval.start, calendar.date(from: DateComponents(year: 2026, month: 9, day: 1)))
        XCTAssertEqual(requests.first?.interval.end, calendar.date(from: DateComponents(year: 2026, month: 10, day: 1)))
    }

    func testSummaryModelStoresFailure() async throws {
        let ownerID = UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let model = DashboardSummaryModel(
            repository: DashboardRepositoryStub(error: AppFailure.unknown),
            context: .personal(ownerID)
        )

        await model.load(period: .day)

        XCTAssertEqual(model.totalMinorUnits, 0)
        XCTAssertEqual(model.failure, .unknown)
        XCTAssertFalse(model.isLoading)
    }

    func testSummaryModelAppliesCurrentPeriodMutationWithoutReloading() async throws {
        let original = try Purchase.quick(
            id: PurchaseID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!),
            ownerID: UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!),
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 1_000, currencyCode: "RUB"),
            spentAt: Date(timeIntervalSince1970: 1_778_284_800),
            localDate: Date(timeIntervalSince1970: 1_778_284_800),
            timeZone: "UTC",
            version: 1
        )
        let updated = try Purchase.quick(
            id: original.id,
            ownerID: original.ownerID,
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 2_500, currencyCode: "RUB"),
            spentAt: original.spentAt,
            localDate: original.localDate,
            timeZone: original.timeZone,
            version: original.version
        )
        let model = DashboardSummaryModel(
            repository: DashboardRepositoryStub(purchases: [original]),
            context: .personal(original.ownerID)
        )
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = Date(timeIntervalSince1970: 1_778_284_800)
        await model.load(period: .day, now: now, calendar: calendar)

        model.applyUpdate(from: original, to: updated, period: .day, now: now, calendar: calendar)
        XCTAssertEqual(model.totalMinorUnits, 2_500)

        model.applyDeletion(updated, period: .day, now: now, calendar: calendar)
        XCTAssertEqual(model.totalMinorUnits, 0)
    }

    func testMonthlyBudgetModelLoadsRealCurrentMonthTotal() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        let purchase = try Purchase.quick(
            id: PurchaseID(rawValue: UUID()),
            ownerID: UserID(rawValue: UUID()),
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 42_000, currencyCode: "RUB"),
            spentAt: now,
            localDate: now,
            timeZone: "UTC",
            version: 1
        )
        let repository = DashboardRepositoryStub(purchases: [purchase])
        let model = DashboardMonthlyBudgetModel(
            repository: repository,
            context: .personal(purchase.ownerID)
        )

        await model.load(now: now, calendar: calendar)

        XCTAssertEqual(model.spentMinorUnits, 42_000)
        let requests = await repository.recordedPurchaseRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests[0].interval, calendar.dateInterval(of: .month, for: now))
    }

    func testMonthlyBudgetModelAppliesUpdatesAndDeletionAcrossMonthBoundary() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = calendar.date(from: DateComponents(year: 2026, month: 9, day: 9, hour: 12))!
        let nextMonth = calendar.date(from: DateComponents(year: 2026, month: 10, day: 1, hour: 12))!
        let original = try Purchase.quick(
            id: PurchaseID(rawValue: UUID()),
            ownerID: UserID(rawValue: UUID()),
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 10_000, currencyCode: "RUB"),
            spentAt: now,
            localDate: now,
            timeZone: "UTC",
            version: 1
        )
        let movedOutsideMonth = try Purchase.quick(
            id: original.id,
            ownerID: original.ownerID,
            groupID: nil,
            merchant: original.merchant,
            category: "Продукты",
            amount: Money(minorUnits: 25_000, currencyCode: "RUB"),
            spentAt: nextMonth,
            localDate: nextMonth,
            timeZone: "UTC",
            version: original.version
        )
        let repository = DashboardRepositoryStub(purchases: [original])
        let model = DashboardMonthlyBudgetModel(
            repository: repository,
            context: .personal(original.ownerID)
        )
        await model.load(now: now, calendar: calendar)

        model.applyUpdate(from: original, to: movedOutsideMonth, now: now, calendar: calendar)
        XCTAssertEqual(model.spentMinorUnits, 0)

        model.applyUpdate(from: movedOutsideMonth, to: original, now: now, calendar: calendar)
        XCTAssertEqual(model.spentMinorUnits, 10_000)

        model.applyDeletion(original, now: now, calendar: calendar)
        XCTAssertEqual(model.spentMinorUnits, 0)
    }

    private func purchase(
        id: String,
        merchant: String,
        kind: Purchase.Kind
    ) throws -> Purchase {
        let ownerID = UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!)
        let date = Date(timeIntervalSince1970: 1_778_284_800)

        switch kind {
        case let .quick(category, amount):
            return try Purchase.quick(
                id: PurchaseID(rawValue: UUID(uuidString: id)!),
                ownerID: ownerID,
                groupID: nil,
                merchant: merchant,
                category: category,
                amount: amount,
                spentAt: date,
                localDate: date,
                timeZone: "UTC",
                version: 1
            )
        case let .detailed(items):
            return try Purchase.detailed(
                id: PurchaseID(rawValue: UUID(uuidString: id)!),
                ownerID: ownerID,
                groupID: nil,
                merchant: merchant,
                items: items,
                spentAt: date,
                localDate: date,
                timeZone: "UTC",
                version: 1
            )
        }
    }
}

private actor DashboardRepositoryStub: PurchaseRepository {
    struct Request: Sendable {
        let cursor: String?
        let limit: Int
    }
    struct PurchaseRequest: Sendable {
        let context: ExpenseContext
        let interval: DateInterval
    }

    private var pages: [PurchasePage]
    private let purchasesSnapshot: [Purchase]
    private let error: Error?
    private var requests: [Request] = []
    private var purchaseRequests: [PurchaseRequest] = []

    init(page: PurchasePage? = nil, purchases: [Purchase] = [], error: Error? = nil) {
        pages = page.map { [$0] } ?? []
        purchasesSnapshot = purchases
        self.error = error
    }

    init(pages: [PurchasePage], purchases: [Purchase] = [], error: Error? = nil) {
        self.pages = pages
        purchasesSnapshot = purchases
        self.error = error
    }

    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] {
        purchaseRequests.append(PurchaseRequest(context: context, interval: interval))
        if let error {
            throw error
        }
        return purchasesSnapshot
    }

    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        requests.append(Request(cursor: cursor, limit: limit))
        if let error {
            throw error
        }
        return pages.isEmpty
            ? PurchasePage(purchases: [], nextCursor: nil, hasMore: false)
            : pages.removeFirst()
    }

    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase {
        throw AppFailure.unknown
    }

    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase {
        throw AppFailure.unknown
    }

    func delete(id: PurchaseID, expectedVersion: Int64) async throws {}

    func recordedRequests() -> [Request] {
        requests
    }

    func recordedPurchaseRequests() -> [PurchaseRequest] {
        purchaseRequests
    }
}

private actor DashboardStatisticsRepositoryStub: StatisticsRepository {
    struct Request: Sendable {
        let context: ExpenseContext
        let interval: DateInterval
    }

    private let snapshot: StatisticsSnapshot?
    private let error: Error?
    private var requests: [Request] = []

    init(snapshot: StatisticsSnapshot? = nil, error: Error? = nil) {
        self.snapshot = snapshot
        self.error = error
    }

    func statistics(in context: ExpenseContext, interval: DateInterval) async throws -> StatisticsSnapshot {
        requests.append(Request(context: context, interval: interval))
        if let error {
            throw error
        }
        return snapshot ?? StatisticsSnapshot(totalMinor: 0, byDay: [:], byCategory: [:])
    }

    func recordedRequests() -> [Request] {
        requests
    }
}
