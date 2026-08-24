import Foundation

protocol MutationQueue: Sendable {
    func nextMutation(readyAt date: Date, ownerID: UserID) async throws -> QueuedMutation?
    func complete(id: UUID) async throws
    func scheduleRetry(id: UUID, at date: Date) async throws
    func requireResolution(id: UUID, failure: MutationFailure) async throws
}

protocol MutationExecutor: Sendable {
    func execute(_ mutation: QueuedMutation) async throws
}

protocol SyncPageSource: Sendable {
    func page(after cursor: String?, in context: ExpenseContext) async throws -> SyncPage
}

protocol SyncPageCache: Sendable {
    func syncCursor(for context: ExpenseContext) async throws -> String?
    func apply(page: SyncPage, in context: ExpenseContext) async throws
}

extension SwiftDataStore: MutationQueue, MutationOutbox, SyncPageCache {}

actor SyncEngine {
    private let queue: any MutationQueue
    private let executor: any MutationExecutor
    private let source: (any SyncPageSource)?
    private let cache: (any SyncPageCache)?
    private let now: @Sendable () -> Date
    private let jitter: @Sendable (TimeInterval) -> TimeInterval
    private var isFlushing = false
    private var requestedOwners: Set<UserID> = []

    init(
        queue: any MutationQueue,
        executor: any MutationExecutor,
        source: (any SyncPageSource)? = nil,
        cache: (any SyncPageCache)? = nil,
        now: @escaping @Sendable () -> Date = Date.init,
        jitter: @escaping @Sendable (TimeInterval) -> TimeInterval = { _ in Double.random(in: 0.8...1.2) }
    ) {
        self.queue = queue
        self.executor = executor
        self.source = source
        self.cache = cache
        self.now = now
        self.jitter = jitter
    }

    func synchronize(in context: ExpenseContext, for ownerID: UserID) async {
        await flushMutations(for: ownerID)
        guard let source, let cache else { return }
        do {
            var cursor = try await cache.syncCursor(for: context)
            while true {
                let page = try await source.page(after: cursor, in: context)
                try await cache.apply(page: page, in: context)
                guard page.changes.count == 100, page.nextCursor != cursor else { return }
                cursor = page.nextCursor
            }
        } catch {
            // A later foreground/background trigger retries remote synchronization.
        }
    }

    func flushMutations(for ownerID: UserID) async {
        guard !isFlushing else {
            requestedOwners.insert(ownerID)
            return
        }
        isFlushing = true
        defer {
            isFlushing = false
            if let requestedOwner = requestedOwners.first {
                requestedOwners.remove(requestedOwner)
                Task { await self.flushMutations(for: requestedOwner) }
            }
        }
        while true {
            do {
                guard let mutation = try await queue.nextMutation(readyAt: now(), ownerID: ownerID) else { return }
                do {
                    try await executor.execute(mutation)
                    try await queue.complete(id: mutation.id)
                } catch is CancellationError {
                    return
                } catch AppFailure.unauthenticated {
                    return
                } catch {
                    if let failure = resolutionFailure(error) {
                        try await queue.requireResolution(id: mutation.id, failure: failure)
                    } else if isRetryable(error) {
                        let attempt = mutation.attempts + 1
                        let baseDelay = pow(2, Double(min(attempt, 8)))
                        let delay = baseDelay * jitter(baseDelay)
                        try await queue.scheduleRetry(id: mutation.id, at: now().addingTimeInterval(delay))
                    } else {
                        try await queue.requireResolution(id: mutation.id, failure: .permanent)
                    }
                    return
                }
            } catch {
                return
            }
        }
    }

    private func resolutionFailure(_ error: Error) -> MutationFailure? {
        guard let failure = error as? AppFailure else { return nil }
        switch failure {
        case .conflict: return MutationFailure.conflict
        case .forbidden: return MutationFailure.forbidden
        case .validation: return MutationFailure.validation
        default: return nil
        }
    }

    private func isRetryable(_ error: Error) -> Bool {
        if let failure = error as? AppFailure {
            switch failure {
            case .network, .offline, .server, .rateLimited: return true
            default: return false
            }
        }
        if let apiError = error as? APIError {
            switch apiError {
            case .network: return true
            case let .server(status, _, _, _): return status >= 500 || status == 429
            default: return false
            }
        }
        return false
    }
}

actor RemoteMutationExecutor: MutationExecutor {
    private let repository: any PurchaseRepository
    init(repository: any PurchaseRepository) { self.repository = repository }

    func execute(_ mutation: QueuedMutation) async throws {
        switch mutation.operation {
        case let .create(draft, key): _ = try await repository.create(draft, idempotencyKey: key)
        case let .update(purchase, version): _ = try await repository.update(purchase, expectedVersion: version)
        case let .delete(id, _, version): try await repository.delete(id: id, expectedVersion: version)
        }
    }
}

actor RemoteSyncPageSource: SyncPageSource {
    private let apiClient: APIClient
    init(apiClient: APIClient) { self.apiClient = apiClient }

    func page(after cursor: String?, in context: ExpenseContext) async throws -> SyncPage {
        var query = [URLQueryItem(name: "limit", value: "100")]
        if let cursor { query.append(URLQueryItem(name: "cursor", value: cursor)) }
        if case let .group(groupID) = context {
            query.append(URLQueryItem(name: "group_id", value: groupID.rawValue.uuidString.lowercased()))
        }
        do {
            let response = try await apiClient.send(
                APIEndpoint<SyncPageDTO>.get("/v1/sync", queryItems: query, requiresAuthorization: true)
            )
            return SyncPage(
                changes: try response.changes.map {
                    SyncChange(purchase: try RepositoryMapping.purchase(from: $0.purchase), deleted: $0.deleted)
                },
                nextCursor: response.nextCursor
            )
        } catch { throw RepositoryMapping.failure(from: error) }
    }
}
