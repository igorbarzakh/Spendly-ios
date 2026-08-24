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
