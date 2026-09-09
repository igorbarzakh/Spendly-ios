import Foundation
import XCTest
@testable import Spendly

@MainActor
final class AllTransactionsModelTests: XCTestCase {
    func testLoadsFirstPageAndPrefetchesNextPageNearListEnd() async throws {
        let first = try purchase(id: "11111111-1111-4111-8111-111111111111", day: 7)
        let second = try purchase(id: "22222222-2222-4222-8222-222222222222", day: 6)
        let repository = AllTransactionsRepositoryStub(pages: [
            PurchasePage(purchases: [first], nextCursor: "next", hasMore: true),
            PurchasePage(purchases: [second], nextCursor: nil, hasMore: false)
        ])
        let model = AllTransactionsModel(
            repository: repository,
            context: .personal(first.ownerID)
        )

        await model.loadInitial()
        await model.loadMoreIfNeeded(current: first)

        XCTAssertEqual(model.purchases.map(\.id), [first.id, second.id])
        XCTAssertFalse(model.hasMore)
        XCTAssertNil(model.failure)
        let requests = await repository.recordedRequests()
        XCTAssertEqual(requests.map(\.cursor), [nil, "next"])
        XCTAssertEqual(requests.map(\.limit), [50, 50])
    }

    func testGroupsTransactionsByDayAndAddsYearOnlyForOlderDates() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let current = try purchase(id: "11111111-1111-4111-8111-111111111111", year: 2026, month: 9, day: 7)
        let older = try purchase(id: "22222222-2222-4222-8222-222222222222", year: 2025, month: 12, day: 31)

        let sections = AllTransactionsSection.make(
            from: [older, current],
            now: calendar.date(from: DateComponents(year: 2026, month: 9, day: 8))!,
            calendar: calendar
        )

        XCTAssertEqual(sections.map(\.purchases), [[current], [older]])
        XCTAssertEqual(sections[0].title, "7 сентября")
        XCTAssertEqual(sections[1].title, "31 декабря 2025")
    }

    func testTodaySectionUsesRelativeTitle() throws {
        var localDateCalendar = Calendar(identifier: .gregorian)
        localDateCalendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var deviceCalendar = Calendar(identifier: .gregorian)
        deviceCalendar.timeZone = TimeZone(identifier: "Europe/Moscow")!
        let today = try purchase(id: "11111111-1111-4111-8111-111111111111", year: 2026, month: 9, day: 8)

        let sections = AllTransactionsSection.make(
            from: [today],
            now: deviceCalendar.date(from: DateComponents(year: 2026, month: 9, day: 8, hour: 0, minute: 40))!,
            calendar: localDateCalendar,
            currentCalendar: deviceCalendar
        )

        XCTAssertEqual(sections.map(\.title), ["Сегодня"])
    }

    func testAppliesUpdatedPurchaseToLoadedList() async throws {
        let original = try purchase(id: "11111111-1111-4111-8111-111111111111", day: 8)
        let updated = try Purchase.quick(
            id: original.id,
            ownerID: original.ownerID,
            groupID: original.groupID,
            merchant: "Updated market",
            category: "Транспорт",
            amount: Money(minorUnits: 9_900, currencyCode: "RUB"),
            spentAt: original.spentAt,
            localDate: original.localDate,
            timeZone: original.timeZone,
            version: original.version
        )
        let model = AllTransactionsModel(
            repository: AllTransactionsRepositoryStub(pages: [
                PurchasePage(purchases: [original], nextCursor: nil, hasMore: false)
            ]),
            context: .personal(original.ownerID)
        )
        await model.loadInitial()

        model.applyUpdatedPurchase(updated)

        XCTAssertEqual(model.purchases, [updated])
    }

    func testRemovesDeletedPurchaseFromLoadedList() async throws {
        let first = try purchase(id: "11111111-1111-4111-8111-111111111111", day: 8)
        let second = try purchase(id: "22222222-2222-4222-8222-222222222222", day: 7)
        let model = AllTransactionsModel(
            repository: AllTransactionsRepositoryStub(pages: [
                PurchasePage(purchases: [first, second], nextCursor: nil, hasMore: false)
            ]),
            context: .personal(first.ownerID)
        )
        await model.loadInitial()

        model.removeDeletedPurchase(id: first.id)

        XCTAssertEqual(model.purchases, [second])
    }

    private func purchase(
        id: String,
        year: Int = 2026,
        month: Int = 9,
        day: Int
    ) throws -> Purchase {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
        return try Purchase.quick(
            id: PurchaseID(rawValue: UUID(uuidString: id)!),
            ownerID: UserID(rawValue: UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!),
            groupID: nil,
            merchant: "Market",
            category: "Продукты",
            amount: Money(minorUnits: 1_250, currencyCode: "RUB"),
            spentAt: date,
            localDate: date,
            timeZone: "UTC",
            version: 1
        )
    }
}

private actor AllTransactionsRepositoryStub: PurchaseRepository {
    struct Request: Sendable {
        let cursor: String?
        let limit: Int
    }

    private var pages: [PurchasePage]
    private var requests: [Request] = []

    init(pages: [PurchasePage]) {
        self.pages = pages
    }

    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] {
        []
    }

    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage {
        requests.append(Request(cursor: cursor, limit: limit))
        return pages.removeFirst()
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
}
