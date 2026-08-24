struct UserSession: Codable, Sendable, Hashable {
    let userID: UserID
}

protocol SessionRepository: Sendable {
    func currentSession() async throws -> UserSession?
    func signOut() async throws
}

