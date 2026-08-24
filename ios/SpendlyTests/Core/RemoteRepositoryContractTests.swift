import Foundation
import XCTest
@testable import Spendly

final class RemoteRepositoryContractTests: XCTestCase {
    private let baseURL = URL(string: "https://api.spendly.app")!
    private let ownerID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let purchaseID = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
    private let groupID = UUID(uuidString: "33333333-3333-4333-8333-333333333333")!

    func testMapsQuickAndDetailedPurchasesFromWireFormat() async throws {
        let transport = RepositoryTransport(responses: [.json(200, purchasesJSON)])
        let repository = RemotePurchaseRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))

        let purchases = try await repository.purchases(
            in: .personal(UserID(rawValue: ownerID)),
            interval: DateInterval(start: date("2026-08-01T00:00:00Z"), end: date("2026-09-01T00:00:00Z"))
        )

        XCTAssertEqual(purchases.count, 2)
        XCTAssertEqual(purchases[0].id, PurchaseID(rawValue: purchaseID))
        XCTAssertEqual(purchases[0].total, try Money(minorUnits: 1_250, currencyCode: "RUB"))
        guard case let .detailed(items) = purchases[1].kind else {
            return XCTFail("Expected a detailed purchase")
        }
        XCTAssertEqual(items.map(\.amount.minorUnits), [800, 450])
    }

    func testUsesCachedPurchasesWithoutNetworkRequest() async throws {
        let cachedPurchase = try makeQuickPurchase()
        let cache = RepositoryCache(snapshot: [cachedPurchase])
        let transport = RepositoryTransport(responses: [])
        let repository = RemotePurchaseRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            cache: cache
        )

        let purchases = try await repository.purchases(
            in: .personal(UserID(rawValue: ownerID)),
            interval: DateInterval(start: date("2026-08-01T00:00:00Z"), end: date("2026-09-01T00:00:00Z"))
        )

        XCTAssertEqual(purchases, [cachedPurchase])
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testCreatePreservesClientIDAndIdempotencyKey() async throws {
        let transport = RepositoryTransport(responses: [.json(201, quickPurchaseJSON)])
        let repository = RemotePurchaseRepository(apiClient: APIClient(baseURL: baseURL, transport: transport))
        let key = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let draft = PurchaseDraft(
            id: PurchaseID(rawValue: purchaseID),
            ownerID: UserID(rawValue: ownerID),
            groupID: nil,
            merchant: "Market",
            spentAt: date("2026-08-24T12:00:00Z"),
            localDate: localDate("2026-08-24"),
            timeZone: "Europe/Moscow",
            kind: .quick(category: "Food", amount: try Money(minorUnits: 1_250, currencyCode: "RUB"))
        )

        _ = try await repository.create(draft, idempotencyKey: key)

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), key.uuidString.lowercased())
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: try XCTUnwrap(request.httpBody)) as? [String: Any])
        XCTAssertEqual(body["id"] as? String, purchaseID.uuidString.uppercased())
        XCTAssertEqual(body["local_date"] as? String, "2026-08-24")
        XCTAssertNil(body["owner_id"])
        XCTAssertNil(body["version"])
    }

    func testMapsVersionConflictWithoutOverwritingCache() async throws {
        let cachedPurchase = try makeQuickPurchase()
        let cache = RepositoryCache(snapshot: [cachedPurchase])
        let transport = RepositoryTransport(responses: [
            .json(409, #"{"error":{"code":"version_conflict","message":"Purchase changed","request_id":"req-1"}}"#)
        ])
        let repository = RemotePurchaseRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            cache: cache
        )

        do {
            _ = try await repository.update(cachedPurchase, expectedVersion: 1)
            XCTFail("Expected conflict")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .conflict)
        }
        let snapshot = await cache.currentSnapshot()
        XCTAssertEqual(snapshot, [cachedPurchase])
    }

    func testOfflineCreateUsesOutboxAndOptimisticCacheWithoutDirectNetworkSend() async throws {
        let transport = RepositoryTransport(responses: [])
        let outbox = RepositoryOutbox()
        let cache = RepositoryCache()
        let repository = RemotePurchaseRepository(
            apiClient: APIClient(baseURL: baseURL, transport: transport),
            cache: cache,
            outbox: outbox
        )
        let purchase = try makeQuickPurchase()
        let draft = PurchaseDraft(
            id: purchase.id, ownerID: purchase.ownerID, groupID: nil, merchant: purchase.merchant,
            spentAt: purchase.spentAt, localDate: purchase.localDate, timeZone: purchase.timeZone,
            kind: purchase.kind
        )
        let key = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!

        let optimistic = try await repository.create(draft, idempotencyKey: key)

        let queued = await outbox.queuedMutations()
        let snapshot = await cache.currentSnapshot()
        let requestCount = await transport.requestCount()
        XCTAssertEqual(queued.first?.operation.idempotencyKey, key)
        XCTAssertEqual(queued.count, 1)
        XCTAssertEqual(snapshot, [optimistic])
        XCTAssertEqual(requestCount, 0)
    }

    func testMapsGroupsAndStatistics() async throws {
        let transport = RepositoryTransport(responses: [
            .json(200, groupsJSON),
            .json(200, #"{"total_minor":2500,"by_day":{"2026-08-24":2500},"by_category":{"Food":2500}}"#)
        ])
        let client = APIClient(baseURL: baseURL, transport: transport)
        let groups = try await RemoteGroupRepository(apiClient: client).groups()
        let statistics = try await RemoteStatisticsRepository(apiClient: client).statistics(
            in: .group(GroupID(rawValue: groupID)),
            interval: DateInterval(start: date("2026-08-01T00:00:00Z"), end: date("2026-09-01T00:00:00Z"))
        )

        XCTAssertEqual(groups.first?.id, GroupID(rawValue: groupID))
        XCTAssertEqual(groups.first?.name, "Family")
        XCTAssertEqual(statistics.totalMinor, 2_500)
        XCTAssertEqual(statistics.byCategory, ["Food": 2_500])
        let requests = await transport.requests()
        XCTAssertEqual(requests[1].url?.query?.contains("group_id=33333333-3333-4333-8333-333333333333"), true)
    }

    func testGroupSyncSendsScopeAndRateLimitIsRetryable() async throws {
        let transport = RepositoryTransport(responses: [
            .json(200, #"{"changes":[],"next_cursor":"cursor-1"}"#)
        ])
        let source = RemoteSyncPageSource(apiClient: APIClient(baseURL: baseURL, transport: transport))

        _ = try await source.page(after: nil, in: .group(GroupID(rawValue: groupID)))

        let requests = await transport.requests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertTrue(request.url?.query?.contains("group_id=33333333-3333-4333-8333-333333333333") == true)
        let failure = RepositoryMapping.failure(
            from: APIError.server(statusCode: 429, code: "rate_limited", message: "Slow down", requestID: "req")
        )
        XCTAssertEqual(failure as? AppFailure, .rateLimited(retryAfter: nil))
    }

    private func makeQuickPurchase() throws -> Purchase {
        try Purchase.quick(
            id: PurchaseID(rawValue: purchaseID), ownerID: UserID(rawValue: ownerID), groupID: nil,
            merchant: "Market", category: "Food", amount: Money(minorUnits: 1_250, currencyCode: "RUB"),
            spentAt: date("2026-08-24T12:00:00Z"), localDate: localDate("2026-08-24"),
            timeZone: "Europe/Moscow", version: 1
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func localDate(_ value: String) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.date(from: DateComponents(year: Int(value.prefix(4)), month: Int(value.dropFirst(5).prefix(2)), day: Int(value.suffix(2))))!
    }

    private var quickPurchaseJSON: String {
        #"{"id":"\#(purchaseID.uuidString)","kind":"quick","merchant":"Market","category":"Food","amount_minor":1250,"currency_code":"RUB","spent_at":"2026-08-24T12:00:00Z","local_date":"2026-08-24","time_zone":"Europe/Moscow","items":[],"owner_id":"\#(ownerID.uuidString)","version":1,"total_amount_minor":1250,"created_at":"2026-08-24T12:00:01Z","updated_at":"2026-08-24T12:00:01Z"}"#
    }

    private var purchasesJSON: String {
        let detailedID = "44444444-4444-4444-8444-444444444444"
        return #"{"purchases":[\#(quickPurchaseJSON),{"id":"\#(detailedID)","group_id":"\#(groupID.uuidString)","kind":"detailed","merchant":"Cafe","currency_code":"RUB","spent_at":"2026-08-25T13:00:00.123Z","local_date":"2026-08-25","time_zone":"Europe/Moscow","items":[{"id":"55555555-5555-4555-8555-555555555555","position":0,"name":"Lunch","category":"Food","amount_minor":800,"created_at":"2026-08-25T13:00:01Z","updated_at":"2026-08-25T13:00:01Z"},{"id":"66666666-6666-4666-8666-666666666666","position":1,"name":"Coffee","category":"Food","amount_minor":450,"created_at":"2026-08-25T13:00:01Z","updated_at":"2026-08-25T13:00:01Z"}],"owner_id":"\#(ownerID.uuidString)","version":2,"total_amount_minor":1250,"created_at":"2026-08-25T13:00:01Z","updated_at":"2026-08-25T13:00:01Z"}]}"#
    }

    private var groupsJSON: String {
        #"{"groups":[{"id":"\#(groupID.uuidString)","name":"Family","owner_id":"\#(ownerID.uuidString)","created_at":"2026-08-01T00:00:00Z","updated_at":"2026-08-01T00:00:00Z"}]}"#
    }
}

private actor RepositoryTransport: HTTPTransport {
    enum Response: Sendable { case json(Int, String) }
    private var stubs: [Response]
    private var recorded: [URLRequest] = []
    init(responses: [Response]) { stubs = responses }
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.append(request)
        guard !stubs.isEmpty else { throw APIError.network }
        let stub = stubs.removeFirst()
        switch stub {
        case let .json(status, body):
            return (Data(body.utf8), HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
        }
    }
    func requests() -> [URLRequest] { recorded }
    func requestCount() -> Int { recorded.count }
}

private actor RepositoryCache: PurchaseCache {
    private var snapshot: [Purchase]?
    init(snapshot: [Purchase]? = nil) { self.snapshot = snapshot }
    func cachedPurchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase]? { snapshot }
    func store(_ purchases: [Purchase], in context: ExpenseContext, interval: DateInterval) async throws { snapshot = purchases }
    func upsert(_ purchase: Purchase) async throws { snapshot = [purchase] }
    func remove(id: PurchaseID) async throws { snapshot?.removeAll { $0.id == id } }
    func currentSnapshot() -> [Purchase]? { snapshot }
}

private actor RepositoryOutbox: MutationOutbox {
    private var values: [QueuedMutation] = []
    func enqueue(_ operation: MutationOperation, createdAt: Date) async throws -> QueuedMutation {
        let value = QueuedMutation(
            id: UUID(), operation: operation, createdAt: createdAt, attempts: 0,
            nextAttemptAt: nil, state: .pending, lastFailure: nil
        )
        values.append(value)
        return value
    }
    func complete(id: UUID) async throws { values.removeAll { $0.id == id } }
    func queuedMutations() -> [QueuedMutation] { values }
}
