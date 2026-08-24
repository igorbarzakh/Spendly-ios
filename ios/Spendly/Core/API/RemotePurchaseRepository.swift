import Foundation

protocol PurchaseCache: Sendable {
    func cachedPurchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase]?
    func store(_ purchases: [Purchase], in context: ExpenseContext, interval: DateInterval) async throws
    func upsert(_ purchase: Purchase) async throws
    func remove(id: PurchaseID) async throws
}

protocol MutationOutbox: Sendable {
    func enqueue(_ operation: MutationOperation, createdAt: Date) async throws -> QueuedMutation
    func complete(id: UUID) async throws
}

actor RemotePurchaseRepository: PurchaseRepository {
    private let apiClient: APIClient
    private let cache: (any PurchaseCache)?
    private let outbox: (any MutationOutbox)?
    private let currentUserID: @Sendable () async throws -> UserID?
    private let didEnqueue: @Sendable () async -> Void

    init(
        apiClient: APIClient,
        cache: (any PurchaseCache)? = nil,
        outbox: (any MutationOutbox)? = nil,
        currentUserID: @escaping @Sendable () async throws -> UserID? = { nil },
        didEnqueue: @escaping @Sendable () async -> Void = {}
    ) {
        self.apiClient = apiClient
        self.cache = cache
        self.outbox = outbox
        self.currentUserID = currentUserID
        self.didEnqueue = didEnqueue
    }

    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase] {
        if let cached = try await cache?.cachedPurchases(in: context, interval: interval) {
            return cached
        }
        do {
            let response = try await apiClient.send(
                APIEndpoint<PurchasesResponseDTO>.get(
                    "/v1/purchases",
                    queryItems: RepositoryMapping.queryItems(context: context, interval: interval),
                    requiresAuthorization: true
                )
            )
            let purchases = try response.purchases.map(RepositoryMapping.purchase(from:))
            try await cache?.store(purchases, in: context, interval: interval)
            return purchases
        } catch {
            throw RepositoryMapping.failure(from: error)
        }
    }

    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase {
        if let outbox {
            _ = try await outbox.enqueue(
                .create(draft: draft, idempotencyKey: idempotencyKey), createdAt: Date()
            )
            let optimistic = try RepositoryMapping.optimisticPurchase(from: draft)
            try await cache?.upsert(optimistic)
            await didEnqueue()
            return optimistic
        }
        do {
            let endpoint = try APIEndpoint<PurchaseDTO>.request(
                "/v1/purchases", method: .post, body: RepositoryMapping.dto(from: draft),
                requiresAuthorization: true,
                headers: ["Idempotency-Key": idempotencyKey.uuidString.lowercased()]
            )
            let purchase = try RepositoryMapping.purchase(from: await apiClient.send(endpoint))
            try await cache?.upsert(purchase)
            return purchase
        } catch {
            throw RepositoryMapping.failure(from: error)
        }
    }

    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase {
        if let outbox {
            _ = try await outbox.enqueue(
                .update(purchase: purchase, expectedVersion: expectedVersion), createdAt: Date()
            )
            try await cache?.upsert(purchase)
            await didEnqueue()
            return purchase
        }
        do {
            let endpoint = try APIEndpoint<PurchaseDTO>.request(
                "/v1/purchases/\(purchase.id.rawValue.uuidString.lowercased())", method: .put,
                body: RepositoryMapping.dto(from: purchase), requiresAuthorization: true,
                headers: ["If-Match": String(expectedVersion)]
            )
            let updated = try RepositoryMapping.purchase(from: await apiClient.send(endpoint))
            try await cache?.upsert(updated)
            return updated
        } catch {
            throw RepositoryMapping.failure(from: error)
        }
    }

    func delete(id: PurchaseID, expectedVersion: Int64) async throws {
        let queued: QueuedMutation?
        if let outbox {
            guard let ownerID = try await currentUserID() else { throw AppFailure.unauthenticated }
            queued = try await outbox.enqueue(
                .delete(id: id, ownerID: ownerID, expectedVersion: expectedVersion), createdAt: Date()
            )
        } else {
            queued = nil
        }
        if queued != nil {
            try await cache?.remove(id: id)
            await didEnqueue()
            return
        }
        do {
            let endpoint = APIEndpoint<EmptyResponseDTO>.request(
                "/v1/purchases/\(id.rawValue.uuidString.lowercased())", method: .delete,
                requiresAuthorization: true, headers: ["If-Match": String(expectedVersion)]
            )
            _ = try await apiClient.send(endpoint)
            try await cache?.remove(id: id)
        } catch {
            throw RepositoryMapping.failure(from: error)
        }
    }
}
