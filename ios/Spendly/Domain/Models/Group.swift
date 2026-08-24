import Foundation

struct Group: Codable, Sendable, Hashable {
    let id: GroupID
    let name: String
    let ownerID: UserID
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

