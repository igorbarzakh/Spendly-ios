import Foundation

enum AuthenticationProvider: String, CaseIterable, Sendable {
    case apple
    case google
}

struct ProviderCredential: Sendable, Equatable {
    let provider: AuthenticationProvider
    let idToken: String
    let nonce: String
}

struct UserSession: Codable, Sendable, Hashable {
    let userID: UserID
}

protocol SessionRepository: Sendable {
    func currentSession() async throws -> UserSession?
    func signIn(with credential: ProviderCredential) async throws -> UserSession
    func accessToken() async throws -> String?
    func signOut() async throws
}
