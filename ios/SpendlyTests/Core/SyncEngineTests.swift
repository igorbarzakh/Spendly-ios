import Foundation
import SwiftData
import XCTest
@testable import Spendly

@MainActor
final class SyncEngineTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_598_000)
    private let ownerID = UserID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!)

    func testProcessesMutationsInFIFOOrder() async throws {
        let store = try makeStore()
        let first = try await store.enqueue(.delete(id: purchaseID(1), ownerID: ownerID, expectedVersion: 1), createdAt: now)
        let second = try await store.enqueue(.delete(id: purchaseID(2), ownerID: ownerID, expectedVersion: 1), createdAt: now.addingTimeInterval(1))
        let executor = MutationExecutorStub(results: [.success(()), .success(())])
        let engine = SyncEngine(queue: store, executor: executor, now: { [now] in now })

        await engine.flushMutations(for: ownerID)

        let executedIDs = await executor.executedIDs()
        let remaining = try await store.mutations()
        XCTAssertEqual(executedIDs, [first.id, second.id])
        XCTAssertTrue(remaining.isEmpty)
    }

    func testRetryKeepsIdempotencyKeyAndUsesExponentialBackoff() async throws {
        let store = try makeStore()
        let key = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        let draft = try makeDraft()
        let mutation = try await store.enqueue(.create(draft: draft, idempotencyKey: key), createdAt: now)
        let executor = MutationExecutorStub(results: [.failure(AppFailure.network)])
        let engine = SyncEngine(queue: store, executor: executor, now: { [now] in now }, jitter: { _ in 1 })

        await engine.flushMutations(for: ownerID)

        let mutations = try await store.mutations()
        let saved = try XCTUnwrap(mutations.first)
        XCTAssertEqual(saved.id, mutation.id)
        XCTAssertEqual(saved.operation.idempotencyKey, key)
        XCTAssertEqual(saved.attempts, 1)
        XCTAssertEqual(saved.nextAttemptAt, now.addingTimeInterval(2))
    }

    func testMutationAndIdempotencyKeySurviveStoreReopen() async throws {
        let url = FileManager.default.temporaryDirectory
            .appending(path: "spendly-sync-\(UUID().uuidString).store")
        let key = UUID(uuidString: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa")!
        var store: SwiftDataStore? = try SwiftDataStore(storeURL: url)
        _ = try await store?.enqueue(.create(draft: makeDraft(), idempotencyKey: key), createdAt: now)
        store = nil

        let reopened = try SwiftDataStore(storeURL: url)
        let mutations = try await reopened.mutations()

        XCTAssertEqual(mutations.count, 1)
        XCTAssertEqual(mutations.first?.operation.idempotencyKey, key)
    }

    func testDoesNotSkipDelayedMutationToExecuteNewerWork() async throws {
        let store = try makeStore()
        let first = try await store.enqueue(.delete(id: purchaseID(1), ownerID: ownerID, expectedVersion: 1), createdAt: now)
        _ = try await store.enqueue(.delete(id: purchaseID(2), ownerID: ownerID, expectedVersion: 1), createdAt: now.addingTimeInterval(1))
        try await store.scheduleRetry(id: first.id, at: now.addingTimeInterval(60))
        let executor = MutationExecutorStub(results: [.success(())])
        let engine = SyncEngine(queue: store, executor: executor, now: { [now] in now })

        await engine.flushMutations(for: ownerID)

        let executed = await executor.executedIDs()
        XCTAssertEqual(executed, [])
    }

    func testVersionConflictRequiresResolutionAndIsNotRetried() async throws {
        let store = try makeStore()
        _ = try await store.enqueue(.update(purchase: makePurchase(version: 1), expectedVersion: 1), createdAt: now)
        _ = try await store.enqueue(
            .delete(id: purchaseID(2), ownerID: ownerID, expectedVersion: 1),
            createdAt: now.addingTimeInterval(1)
        )
        let executor = MutationExecutorStub(results: [.failure(AppFailure.conflict), .success(())])
        let engine = SyncEngine(queue: store, executor: executor, now: { [now] in now })

        await engine.flushMutations(for: ownerID)
        await engine.flushMutations(for: ownerID)

        let mutations = try await store.mutations()
        let saved = try XCTUnwrap(mutations.first)
        XCTAssertEqual(saved.state, .requiresResolution)
        XCTAssertEqual(saved.lastFailure, .conflict)
        XCTAssertEqual(mutations.count, 2)
        let executionCount = await executor.executedIDs().count
        XCTAssertEqual(executionCount, 1)
    }

    func testCancellationLeavesMutationPending() async throws {
        let store = try makeStore()
        _ = try await store.enqueue(.delete(id: purchaseID(1), ownerID: ownerID, expectedVersion: 1), createdAt: now)
        let executor = MutationExecutorStub(results: [.failure(CancellationError())])
        let engine = SyncEngine(queue: store, executor: executor, now: { [now] in now })

        await engine.flushMutations(for: ownerID)

        let mutations = try await store.mutations()
        let mutation = try XCTUnwrap(mutations.first)
        XCTAssertEqual(mutation.state, .pending)
        XCTAssertEqual(mutation.attempts, 0)
    }

    func testSyncCursorIsIsolatedByUserAndGroup() async throws {
        let store = try makeStore()
        let personal = ExpenseContext.personal(UserID(rawValue: UUID(uuidString: "11111111-1111-4111-8111-111111111111")!))
        let group = ExpenseContext.group(GroupID(rawValue: UUID(uuidString: "33333333-3333-4333-8333-333333333333")!))
        try await store.apply(page: SyncPage(changes: [], nextCursor: "personal-cursor"), in: personal)
        try await store.apply(page: SyncPage(changes: [], nextCursor: "group-cursor"), in: group)

        let personalCursor = try await store.syncCursor(for: personal)
        let groupCursor = try await store.syncCursor(for: group)
        XCTAssertEqual(personalCursor, "personal-cursor")
        XCTAssertEqual(groupCursor, "group-cursor")
    }

    func testSynchronizeConsumesAllFullPages() async throws {
        let store = try makeStore()
        let purchase = makePurchase(version: 1)
        let first = SyncPage(
            changes: Array(repeating: SyncChange(purchase: purchase, deleted: false), count: 100),
            nextCursor: "cursor-1"
        )
        let source = SyncSourceStub(pages: [first, SyncPage(changes: [], nextCursor: "cursor-2")])
        let cache = SyncCacheStub()
        let executor = MutationExecutorStub(results: [])
        let engine = SyncEngine(queue: store, executor: executor, source: source, cache: cache)

        await engine.synchronize(in: .personal(purchase.ownerID), for: purchase.ownerID)

        let requestCount = await source.requestCount()
        let cursors = await cache.appliedCursors()
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(cursors, ["cursor-1", "cursor-2"])
    }

    func testSyncPageAppliesTombstoneAndCursorTogether() async throws {
        let store = try makeStore()
        let purchase = makePurchase(version: 1)
        let interval = DateInterval(start: now.addingTimeInterval(-86_400), end: now.addingTimeInterval(86_400))
        let scope = ExpenseContext.personal(purchase.ownerID)
        try await store.store([purchase], in: scope, interval: interval)
        try await store.apply(
            page: SyncPage(changes: [.init(purchase: purchase, deleted: true)], nextCursor: "cursor-2"),
            in: scope
        )

        let cached = try await store.cachedPurchases(in: .personal(purchase.ownerID), interval: interval)
        XCTAssertEqual(cached, [])
        let cursor = try await store.syncCursor(for: scope)
        XCTAssertEqual(cursor, "cursor-2")
    }

    private func makeStore() throws -> SwiftDataStore {
        try SwiftDataStore(inMemory: true)
    }

    private func purchaseID(_ value: Int) -> PurchaseID {
        PurchaseID(rawValue: UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", value))!)
    }

    private func makeDraft() throws -> PurchaseDraft {
        let purchase = makePurchase(version: 1)
        return PurchaseDraft(
            id: purchase.id, ownerID: purchase.ownerID, groupID: purchase.groupID,
            merchant: purchase.merchant, spentAt: purchase.spentAt, localDate: purchase.localDate,
            timeZone: purchase.timeZone, kind: purchase.kind
        )
    }

    private func makePurchase(version: Int64) -> Purchase {
        try! Purchase.quick(
            id: purchaseID(9), ownerID: ownerID,
            groupID: nil, merchant: "Market", category: "Food",
            amount: Money(minorUnits: 500, currencyCode: "RUB"), spentAt: now,
            localDate: now, timeZone: "Europe/Moscow", version: version
        )
    }
}

private actor MutationExecutorStub: MutationExecutor {
    private var results: [Result<Void, Error>]
    private var ids: [UUID] = []
    init(results: [Result<Void, Error>]) { self.results = results }
    func execute(_ mutation: QueuedMutation) async throws {
        ids.append(mutation.id)
        try results.removeFirst().get()
    }
    func executedIDs() -> [UUID] { ids }
}

private actor SyncSourceStub: SyncPageSource {
    private var pages: [SyncPage]
    private var requests = 0
    init(pages: [SyncPage]) { self.pages = pages }
    func page(after cursor: String?, in context: ExpenseContext) async throws -> SyncPage {
        requests += 1
        return pages.removeFirst()
    }
    func requestCount() -> Int { requests }
}

private actor SyncCacheStub: SyncPageCache {
    private var cursors: [String] = []
    func syncCursor(for context: ExpenseContext) async throws -> String? { cursors.last }
    func apply(page: SyncPage, in context: ExpenseContext) async throws { cursors.append(page.nextCursor) }
    func appliedCursors() -> [String] { cursors }
}
