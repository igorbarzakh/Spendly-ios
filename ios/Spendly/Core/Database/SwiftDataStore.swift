import Foundation
import SwiftData

@MainActor
final class SwiftDataStore: PurchaseCache {
    private let container: ModelContainer
    private let context: ModelContext
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(inMemory: Bool = false) throws {
        let schema = Self.schema()
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    init(storeURL: URL) throws {
        let schema = Self.schema()
        let configuration = ModelConfiguration(schema: schema, url: storeURL)
        container = try ModelContainer(for: schema, configurations: [configuration])
        context = ModelContext(container)
    }

    func cachedPurchases(in expenseContext: ExpenseContext, interval: DateInterval) async throws -> [Purchase]? {
        let rangeKey = Self.rangeKey(context: expenseContext, interval: interval)
        let ranges = try context.fetch(FetchDescriptor<CachedRangeRecord>())
        guard ranges.contains(where: { $0.key == rangeKey }) else { return nil }
        return try context.fetch(FetchDescriptor<CachedPurchaseRecord>())
            .filter { !$0.isDeleted && Self.matches($0, context: expenseContext) && interval.contains($0.spentAt) }
            .sorted { $0.spentAt > $1.spentAt }
            .map { try decoder.decode(Purchase.self, from: $0.payload) }
    }

    func store(_ purchases: [Purchase], in expenseContext: ExpenseContext, interval: DateInterval) async throws {
        let records = try context.fetch(FetchDescriptor<CachedPurchaseRecord>())
        for record in records where Self.matches(record, context: expenseContext) && interval.contains(record.spentAt) {
            context.delete(record)
        }
        for purchase in purchases { try insertOrUpdate(purchase, deleted: false) }
        let key = Self.rangeKey(context: expenseContext, interval: interval)
        if !(try context.fetch(FetchDescriptor<CachedRangeRecord>())).contains(where: { $0.key == key }) {
            context.insert(CachedRangeRecord(key: key))
        }
        try context.save()
    }

    func upsert(_ purchase: Purchase) async throws {
        try insertOrUpdate(purchase, deleted: false)
        try context.save()
    }

    func remove(id: PurchaseID) async throws {
        if let record = try record(id: id.rawValue) {
            record.isDeleted = true
            try context.save()
        }
    }

    func apply(page: SyncPage, in expenseContext: ExpenseContext) async throws {
        do {
            for change in page.changes {
                try insertOrUpdate(change.purchase, deleted: change.deleted)
            }
            let cursors = try context.fetch(FetchDescriptor<SyncCursorRecord>())
            let key = Self.cursorKey(context: expenseContext)
            if let cursor = cursors.first(where: { $0.key == key }) {
                cursor.cursor = page.nextCursor
            } else {
                context.insert(SyncCursorRecord(key: key, cursor: page.nextCursor))
            }
            try context.save()
        } catch {
            context.rollback()
            throw error
        }
    }

    func syncCursor(for expenseContext: ExpenseContext) async throws -> String? {
        let key = Self.cursorKey(context: expenseContext)
        return try context.fetch(FetchDescriptor<SyncCursorRecord>()).first(where: { $0.key == key })?.cursor
    }

    @discardableResult
    func enqueue(_ operation: MutationOperation, createdAt: Date = Date()) async throws -> QueuedMutation {
        let id = UUID()
        let existing = try context.fetch(FetchDescriptor<MutationRecord>())
        let sequence = (existing.map(\.sequence).max() ?? 0) + 1
        context.insert(
            MutationRecord(
                id: id, operationData: try encoder.encode(operation),
                createdAt: createdAt, sequence: sequence
            )
        )
        try context.save()
        return QueuedMutation(
            id: id, operation: operation, createdAt: createdAt, attempts: 0,
            nextAttemptAt: nil, state: .pending, lastFailure: nil
        )
    }

    func nextMutation(readyAt date: Date, ownerID: UserID) async throws -> QueuedMutation? {
        guard let first = try await mutations().first(where: { $0.operation.ownerID == ownerID }) else { return nil }
        guard first.state == .pending else { return nil }
        guard first.nextAttemptAt == nil || first.nextAttemptAt! <= date else { return nil }
        return first
    }

    func mutations() async throws -> [QueuedMutation] {
        let descriptor = FetchDescriptor<MutationRecord>(
            sortBy: [SortDescriptor(\MutationRecord.sequence)]
        )
        return try context.fetch(descriptor).map(snapshot(from:))
    }

    func complete(id: UUID) async throws {
        if let value = try mutationRecord(id: id) { context.delete(value); try context.save() }
    }

    func scheduleRetry(id: UUID, at date: Date) async throws {
        guard let value = try mutationRecord(id: id) else { return }
        value.attempts += 1
        value.nextAttemptAt = date
        try context.save()
    }

    func requireResolution(id: UUID, failure: MutationFailure) async throws {
        guard let value = try mutationRecord(id: id) else { return }
        value.stateRawValue = MutationState.requiresResolution.rawValue
        value.lastFailureRawValue = failure.rawValue
        try context.save()
    }

    private func insertOrUpdate(_ purchase: Purchase, deleted: Bool) throws {
        let payload = try encoder.encode(purchase)
        if deleted {
            if let value = try record(id: purchase.id.rawValue) {
                context.delete(value)
            } else {
                context.insert(CachedPurchaseRecord(purchase: purchase, payload: payload, isDeleted: true))
            }
            return
        }
        if let value = try record(id: purchase.id.rawValue) {
            value.ownerID = purchase.ownerID.rawValue
            value.groupID = purchase.groupID?.rawValue
            value.spentAt = purchase.spentAt
            value.payload = payload
            value.isDeleted = false
        } else {
            context.insert(CachedPurchaseRecord(purchase: purchase, payload: payload))
        }
    }

    private func record(id: UUID) throws -> CachedPurchaseRecord? {
        try context.fetch(FetchDescriptor<CachedPurchaseRecord>()).first { $0.id == id }
    }

    private func mutationRecord(id: UUID) throws -> MutationRecord? {
        try context.fetch(FetchDescriptor<MutationRecord>()).first { $0.id == id }
    }

    private func snapshot(from value: MutationRecord) throws -> QueuedMutation {
        guard let state = MutationState(rawValue: value.stateRawValue) else { throw APIError.decoding }
        return QueuedMutation(
            id: value.id, operation: try decoder.decode(MutationOperation.self, from: value.operationData),
            createdAt: value.createdAt, attempts: value.attempts, nextAttemptAt: value.nextAttemptAt,
            state: state, lastFailure: value.lastFailureRawValue.flatMap(MutationFailure.init(rawValue:))
        )
    }

    private static func matches(_ record: CachedPurchaseRecord, context: ExpenseContext) -> Bool {
        switch context {
        case let .personal(ownerID): record.ownerID == ownerID.rawValue
        case let .group(groupID): record.groupID == groupID.rawValue
        }
    }

    private static func rangeKey(context: ExpenseContext, interval: DateInterval) -> String {
        let scope: String
        switch context {
        case let .personal(ownerID): scope = "personal:\(ownerID.rawValue.uuidString)"
        case let .group(groupID): scope = "group:\(groupID.rawValue.uuidString)"
        }
        return "\(scope):\(interval.start.timeIntervalSince1970):\(interval.end.timeIntervalSince1970)"
    }

    private static func cursorKey(context: ExpenseContext) -> String {
        switch context {
        case let .personal(ownerID): "personal:\(ownerID.rawValue.uuidString)"
        case let .group(groupID): "group:\(groupID.rawValue.uuidString)"
        }
    }

    private static func schema() -> Schema {
        Schema([
            CachedPurchaseRecord.self,
            CachedRangeRecord.self,
            SyncCursorRecord.self,
            MutationRecord.self
        ])
    }
}
