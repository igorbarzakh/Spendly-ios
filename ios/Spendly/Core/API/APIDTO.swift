import Foundation

struct APIErrorEnvelopeDTO: Decodable, Sendable {
    let error: APIErrorDTO
}

struct APIErrorDTO: Decodable, Sendable {
    let code: String
    let message: String
    let requestId: String
}

struct ProviderSignInRequestDTO: Encodable, Sendable {
    let idToken: String
    let nonce: String
}

struct RefreshRequestDTO: Encodable, Sendable {
    let refreshToken: String
}

struct SessionDTO: Decodable, Sendable {
    let user: UserDTO?
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
}

struct UserDTO: Decodable, Sendable {
    let id: UUID
    let displayName: String?
    let currencyCode: String?
    let timeZone: String?
}

struct EmptyResponseDTO: Decodable, Sendable {}

struct PurchasesResponseDTO: Decodable, Sendable { let purchases: [PurchaseDTO] }
struct GroupsResponseDTO: Decodable, Sendable { let groups: [GroupDTO] }

struct PurchaseItemDTO: Codable, Sendable {
    let id: UUID
    let position: Int
    let name: String
    let category: String
    let quantity: Int64?
    let unitPriceMinor: Int64?
    let amountMinor: Int64
    let createdAt: Date?
    let updatedAt: Date?
}

struct PurchaseItemDraftDTO: Encodable, Sendable {
    let id: UUID
    let position: Int
    let name: String
    let category: String
    let quantity: Int64?
    let unitPriceMinor: Int64?
    let amountMinor: Int64
}

struct PurchaseDiscountDTO: Codable, Sendable {
    let type: String
    let value: Int64
}

struct PurchaseDraftDTO: Encodable, Sendable {
    let id: UUID
    let groupId: UUID?
    let kind: String
    let merchant: String
    let category: String?
    let amountMinor: Int64?
    let currencyCode: String
    let spentAt: Date
    let localDate: String
    let timeZone: String
    let deliveryFeeMinor: Int64?
    let discount: PurchaseDiscountDTO?
    let items: [PurchaseItemDraftDTO]
}

struct PurchaseDTO: Codable, Sendable {
    let id: UUID
    let groupId: UUID?
    let kind: String
    let merchant: String
    let category: String?
    let amountMinor: Int64?
    let currencyCode: String
    let spentAt: Date
    let localDate: String
    let timeZone: String
    let deliveryFeeMinor: Int64?
    let discount: PurchaseDiscountDTO?
    let items: [PurchaseItemDTO]
    let ownerId: UUID?
    let version: Int64?
    let totalAmountMinor: Int64?
    let createdAt: Date?
    let updatedAt: Date?
    let deletedAt: Date?
}

struct GroupDTO: Decodable, Sendable {
    let id: UUID
    let name: String
    let ownerId: UUID
    let archivedAt: Date?
    let createdAt: Date
    let updatedAt: Date
}

struct CreateGroupDTO: Encodable, Sendable { let id: UUID; let name: String }
struct ArchiveGroupDTO: Encodable, Sendable { let archived: Bool }

struct StatisticsDTO: Decodable, Sendable {
    let totalMinor: Int64
    let byDay: [String: Int64]
    let byCategory: [String: Int64]
}

struct SyncPageDTO: Decodable, Sendable {
    let changes: [SyncChangeDTO]
    let nextCursor: String
}

struct SyncChangeDTO: Decodable, Sendable {
    let purchase: PurchaseDTO
    let deleted: Bool
}
