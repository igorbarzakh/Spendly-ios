import Foundation

struct PurchasePage: Sendable, Equatable {
    let purchases: [Purchase]
    let nextCursor: String?
    let hasMore: Bool
}

protocol PurchaseRepository: Sendable {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase]
    func purchasePage(in context: ExpenseContext, after cursor: String?, limit: Int) async throws -> PurchasePage
    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase
    func delete(id: PurchaseID, expectedVersion: Int64) async throws
}
