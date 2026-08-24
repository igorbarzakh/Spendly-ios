import Foundation
import SwiftData

enum MutationOperation: Codable, Sendable, Equatable {
    case create(draft: PurchaseDraft, idempotencyKey: UUID)
    case update(purchase: Purchase, expectedVersion: Int64)
    case delete(id: PurchaseID, ownerID: UserID, expectedVersion: Int64)

    var idempotencyKey: UUID? {
        if case let .create(_, key) = self { return key }
        return nil
    }

    var ownerID: UserID {
        switch self {
        case let .create(draft, _): draft.ownerID
        case let .update(purchase, _): purchase.ownerID
        case let .delete(_, ownerID, _): ownerID
        }
    }
}

enum MutationState: String, Codable, Sendable, Equatable {
    case pending
    case requiresResolution
}

enum MutationFailure: String, Codable, Sendable, Equatable {
    case conflict
    case forbidden
    case validation
    case permanent
}

struct QueuedMutation: Sendable, Equatable {
    let id: UUID
    let operation: MutationOperation
    let createdAt: Date
    let attempts: Int
    let nextAttemptAt: Date?
    let state: MutationState
    let lastFailure: MutationFailure?
}

@Model
final class MutationRecord {
    @Attribute(.unique) var id: UUID
    var operationData: Data
    var createdAt: Date
    var sequence: Int64
    var attempts: Int
    var nextAttemptAt: Date?
    var stateRawValue: String
    var lastFailureRawValue: String?

    init(id: UUID, operationData: Data, createdAt: Date, sequence: Int64) {
        self.id = id
        self.operationData = operationData
        self.createdAt = createdAt
        self.sequence = sequence
        attempts = 0
        nextAttemptAt = nil
        stateRawValue = MutationState.pending.rawValue
        lastFailureRawValue = nil
    }
}
