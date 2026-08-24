import Foundation

protocol PurchaseRepository: Sendable {
    func purchases(in context: ExpenseContext, interval: DateInterval) async throws -> [Purchase]
    func create(_ draft: PurchaseDraft, idempotencyKey: UUID) async throws -> Purchase
    func update(_ purchase: Purchase, expectedVersion: Int64) async throws -> Purchase
    func delete(id: PurchaseID, expectedVersion: Int64) async throws
}

