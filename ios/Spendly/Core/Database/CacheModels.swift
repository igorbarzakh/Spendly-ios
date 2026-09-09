import Foundation
import SwiftData

@Model
final class CachedPurchaseRecord {
    @Attribute(.unique) var id: UUID
    var ownerID: UUID
    var groupID: UUID?
    var spentAt: Date
    var payload: Data
    @Attribute(originalName: "isDeleted") var isTombstone: Bool

    init(purchase: Purchase, payload: Data, isTombstone: Bool = false) {
        id = purchase.id.rawValue
        ownerID = purchase.ownerID.rawValue
        groupID = purchase.groupID?.rawValue
        spentAt = purchase.spentAt
        self.payload = payload
        self.isTombstone = isTombstone
    }
}

@Model
final class CachedRangeRecord {
    @Attribute(.unique) var key: String
    init(key: String) { self.key = key }
}

@Model
final class SyncCursorRecord {
    @Attribute(.unique) var key: String
    var cursor: String
    init(key: String = "purchases", cursor: String) {
        self.key = key
        self.cursor = cursor
    }
}

struct SyncChange: Sendable, Equatable {
    let purchase: Purchase
    let deleted: Bool
}

struct SyncPage: Sendable, Equatable {
    let changes: [SyncChange]
    let nextCursor: String
}
