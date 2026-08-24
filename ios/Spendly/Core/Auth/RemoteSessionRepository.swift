import Foundation

actor RemoteSessionRepository: SessionRepository {
    private let apiClient: APIClient
    private let store: any SessionStore
    private let now: @Sendable () -> Date
    private var refreshTask: Task<StoredSession, Error>?

    init(
        apiClient: APIClient,
        store: any SessionStore,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.apiClient = apiClient
        self.store = store
        self.now = now
    }

    func currentSession() async throws -> UserSession? {
        guard let storedSession = try await store.load() else {
            return nil
        }
        guard storedSession.refreshExpiresAt > now() else {
            try await store.delete()
            return nil
        }
        if storedSession.accessExpiresAt > now() {
            return UserSession(userID: storedSession.userID)
        }
        let refreshedSession = try await refreshSingleFlight(storedSession)
        return UserSession(userID: refreshedSession.userID)
    }

    func signIn(with credential: ProviderCredential) async throws -> UserSession {
        let endpoint = try APIEndpoint<SessionDTO>.post(
            "/v1/auth/\(credential.provider.rawValue)",
            body: ProviderSignInRequestDTO(idToken: credential.idToken, nonce: credential.nonce)
        )
        let response = try await apiClient.send(endpoint)
        guard let user = response.user else {
            throw APIError.decoding
        }
        let session = StoredSession(
            userID: UserID(rawValue: user.id),
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            accessExpiresAt: response.accessExpiresAt,
            refreshExpiresAt: response.refreshExpiresAt
        )
        try await store.save(session)
        return UserSession(userID: session.userID)
    }

    func accessToken() async throws -> String? {
        guard try await currentSession() != nil else {
            return nil
        }
        return try await store.load()?.accessToken
    }

    func refreshAccessToken() async throws -> String? {
        guard let session = try await store.load(), session.refreshExpiresAt > now() else {
            try await store.delete()
            return nil
        }
        return try await refreshSingleFlight(session).accessToken
    }

    func signOut() async throws {
        guard let session = try await store.load() else {
            return
        }
        let endpoint = try APIEndpoint<EmptyResponseDTO>.post(
            "/v1/auth/logout",
            body: RefreshRequestDTO(refreshToken: session.refreshToken)
        )
        _ = try await apiClient.send(endpoint)
        try await store.delete()
    }

    private func refreshSingleFlight(_ session: StoredSession) async throws -> StoredSession {
        if let refreshTask {
            return try await refreshTask.value
        }

        let task = Task { try await self.performRefresh(session) }
        refreshTask = task
        do {
            let refreshedSession = try await task.value
            refreshTask = nil
            return refreshedSession
        } catch {
            refreshTask = nil
            throw error
        }
    }

    private func performRefresh(_ session: StoredSession) async throws -> StoredSession {
        do {
            let endpoint = try APIEndpoint<SessionDTO>.post(
                "/v1/auth/refresh",
                body: RefreshRequestDTO(refreshToken: session.refreshToken)
            )
            let response = try await apiClient.send(endpoint)
            let refreshedSession = StoredSession(
                userID: session.userID,
                accessToken: response.accessToken,
                refreshToken: response.refreshToken,
                accessExpiresAt: response.accessExpiresAt,
                refreshExpiresAt: response.refreshExpiresAt
            )
            try await store.save(refreshedSession)
            return refreshedSession
        } catch let error as APIError {
            if case let .server(statusCode, _, _, _) = error,
               statusCode == 401 {
                try await store.delete()
                throw AppFailure.unauthenticated
            }
            throw error
        }
    }
}
