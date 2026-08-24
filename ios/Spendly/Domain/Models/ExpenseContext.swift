import Foundation

struct UserID: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

struct GroupID: RawRepresentable, Codable, Sendable, Hashable {
    let rawValue: UUID

    init(rawValue: UUID) {
        self.rawValue = rawValue
    }
}

enum ExpenseContext: Codable, Sendable, Hashable {
    case personal(UserID)
    case group(GroupID)
}

