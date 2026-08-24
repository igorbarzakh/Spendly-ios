import Foundation
import XCTest
@testable import Spendly

final class RemoteSessionRepositoryTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_787_598_000)
    private let userID = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!

    func testFirstLoginExchangesProviderCredentialAndStoresSession() async throws {
        let transport = AuthTransport(responses: [
            .json(statusCode: 200, body: sessionJSON(userID: userID))
        ])
        let store = MemorySessionStore()
        let repository = makeRepository(transport: transport, store: store)
        let credential = ProviderCredential(provider: .google, idToken: "google-token", nonce: "raw-nonce")

        let session = try await repository.signIn(with: credential)

        XCTAssertEqual(session.userID, UserID(rawValue: userID))
        let loadedSession = try await store.load()
        let savedSession = try XCTUnwrap(loadedSession)
        XCTAssertEqual(savedSession.userID, UserID(rawValue: userID))
        XCTAssertEqual(savedSession.accessToken, "access-1")
        XCTAssertEqual(savedSession.refreshToken, "refresh-1")
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/auth/google")
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(
            try decodeBody(request),
            ["id_token": "google-token", "nonce": "raw-nonce"]
        )
    }

    func testRestoresUnexpiredSessionWithoutNetworkRequest() async throws {
        let storedSession = makeStoredSession(accessExpiresAt: now.addingTimeInterval(600))
        let store = MemorySessionStore(session: storedSession)
        let transport = AuthTransport(responses: [])
        let repository = makeRepository(transport: transport, store: store)

        let session = try await repository.currentSession()

        XCTAssertEqual(session, UserSession(userID: storedSession.userID))
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func testRefreshRotatesBothTokensAtomicallyAndKeepsUserIdentity() async throws {
        let storedSession = makeStoredSession(accessExpiresAt: now.addingTimeInterval(-1))
        let store = MemorySessionStore(session: storedSession)
        let transport = AuthTransport(responses: [
            .json(statusCode: 200, body: refreshedSessionJSON)
        ])
        let repository = makeRepository(transport: transport, store: store)

        let session = try await repository.currentSession()

        XCTAssertEqual(session, UserSession(userID: storedSession.userID))
        let loadedSession = try await store.load()
        let rotated = try XCTUnwrap(loadedSession)
        XCTAssertEqual(rotated.userID, storedSession.userID)
        XCTAssertEqual(rotated.accessToken, "access-2")
        XCTAssertEqual(rotated.refreshToken, "refresh-2")
        let saveCount = await store.saveCount()
        XCTAssertEqual(saveCount, 1)
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/auth/refresh")
        XCTAssertEqual(try decodeBody(request), ["refresh_token": "refresh-1"])
    }

    func testConcurrentAccessTokenRequestsShareSingleRefreshRotation() async throws {
        let storedSession = makeStoredSession(accessExpiresAt: now.addingTimeInterval(-1))
        let store = MemorySessionStore(session: storedSession)
        let transport = AuthTransport(responses: [
            .json(statusCode: 200, body: refreshedSessionJSON),
            .json(statusCode: 200, body: refreshedSessionJSON)
        ])
        let repository = makeRepository(transport: transport, store: store)

        async let firstToken = repository.accessToken()
        async let secondToken = repository.accessToken()
        let tokens = try await [firstToken, secondToken]

        XCTAssertEqual(tokens, ["access-2", "access-2"])
        let requestCount = await transport.requestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func testForcedRefreshRotatesAnOtherwiseUnexpiredAccessToken() async throws {
        let storedSession = makeStoredSession(accessExpiresAt: now.addingTimeInterval(600))
        let store = MemorySessionStore(session: storedSession)
        let transport = AuthTransport(responses: [
            .json(statusCode: 200, body: refreshedSessionJSON)
        ])
        let repository = makeRepository(transport: transport, store: store)

        let token = try await repository.refreshAccessToken()

        XCTAssertEqual(token, "access-2")
        let requestCount = await transport.requestCount()
        let refreshedSession = try await store.load()
        XCTAssertEqual(requestCount, 1)
        XCTAssertEqual(refreshedSession?.refreshToken, "refresh-2")
    }

    func testRejectedRefreshDeletesUnusableLocalSession() async throws {
        let store = MemorySessionStore(
            session: makeStoredSession(accessExpiresAt: now.addingTimeInterval(-1))
        )
        let transport = AuthTransport(responses: [
            .json(
                statusCode: 401,
                body: #"{"error":{"code":"unauthorized","message":"Authentication failed","request_id":"req-1"}}"#
            )
        ])
        let repository = makeRepository(transport: transport, store: store)

        do {
            _ = try await repository.currentSession()
            XCTFail("Expected unauthenticated failure")
        } catch let failure as AppFailure {
            XCTAssertEqual(failure, .unauthenticated)
        }

        let storedSession = try await store.load()
        XCTAssertNil(storedSession)
    }

    func testSignInPropagatesSessionStoreFailure() async throws {
        let transport = AuthTransport(responses: [
            .json(statusCode: 200, body: sessionJSON(userID: userID))
        ])
        let store = FailingSessionStore()
        let repository = makeRepository(transport: transport, store: store)

        do {
            _ = try await repository.signIn(
                with: ProviderCredential(provider: .apple, idToken: "apple-token", nonce: "raw-nonce")
            )
            XCTFail("Expected Keychain write failure")
        } catch let error as SessionStoreTestError {
            XCTAssertEqual(error, .writeFailed)
        }
    }

    func testSignOutRevokesRemoteSessionThenClearsLocalTokens() async throws {
        let store = MemorySessionStore(session: makeStoredSession(accessExpiresAt: now.addingTimeInterval(600)))
        let transport = AuthTransport(responses: [.empty(statusCode: 204)])
        let repository = makeRepository(transport: transport, store: store)

        try await repository.signOut()

        let storedSession = try await store.load()
        XCTAssertNil(storedSession)
        let requests = await transport.allRequests()
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.url?.path, "/v1/auth/logout")
        XCTAssertEqual(try decodeBody(request), ["refresh_token": "refresh-1"])
    }

    func testKeychainStoreReplacesTokenPairAsSingleRecord() async throws {
        let store = KeychainSessionStore(
            service: "app.spendly.ios.tests.\(UUID().uuidString)",
            account: "session",
            usesDataProtectionKeychain: false
        )
        let first = makeStoredSession(accessExpiresAt: now.addingTimeInterval(60))
        let second = StoredSession(
            userID: first.userID,
            accessToken: "rotated-access",
            refreshToken: "rotated-refresh",
            accessExpiresAt: now.addingTimeInterval(120),
            refreshExpiresAt: now.addingTimeInterval(172_800)
        )

        try await store.save(first)
        try await store.save(second)
        let loaded = try await store.load()
        try await store.delete()
        let deleted = try await store.load()

        XCTAssertEqual(loaded, second)
        XCTAssertNil(deleted)
    }

    private func makeRepository(
        transport: AuthTransport,
        store: any SessionStore
    ) -> RemoteSessionRepository {
        RemoteSessionRepository(
            apiClient: APIClient(baseURL: URL(string: "https://api.spendly.app")!, transport: transport),
            store: store,
            now: { [now] in now }
        )
    }

    private func decodeBody(_ request: URLRequest) throws -> [String: String] {
        let data = try XCTUnwrap(request.httpBody)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: String])
    }

    private func makeStoredSession(accessExpiresAt: Date) -> StoredSession {
        StoredSession(
            userID: UserID(rawValue: userID),
            accessToken: "access-1",
            refreshToken: "refresh-1",
            accessExpiresAt: accessExpiresAt,
            refreshExpiresAt: now.addingTimeInterval(86_400)
        )
    }

    private func sessionJSON(userID: UUID) -> String {
        """
        {
          "user": {"id": "\(userID.uuidString)"},
          "access_token": "access-1",
          "refresh_token": "refresh-1",
          "access_expires_at": "2026-08-24T18:20:00.123456Z",
          "refresh_expires_at": "2026-09-23T18:20:00Z"
        }
        """
    }

    private var refreshedSessionJSON: String {
        """
        {
          "access_token": "access-2",
          "refresh_token": "refresh-2",
          "access_expires_at": "2026-08-24T19:20:00.654321Z",
          "refresh_expires_at": "2026-09-23T19:20:00Z"
        }
        """
    }
}

private actor AuthTransport: HTTPTransport {
    enum Response: Sendable {
        case json(statusCode: Int, body: String)
        case empty(statusCode: Int)
    }

    private var responses: [Response]
    private var requests: [URLRequest] = []

    init(responses: [Response]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()
        let statusCode: Int
        let data: Data
        switch response {
        case let .json(status, body):
            statusCode = status
            data = Data(body.utf8)
        case let .empty(status):
            statusCode = status
            data = Data()
        }
        return (
            data,
            HTTPURLResponse(url: request.url!, statusCode: statusCode, httpVersion: nil, headerFields: nil)!
        )
    }

    func allRequests() -> [URLRequest] { requests }
    func requestCount() -> Int { requests.count }
}

private actor MemorySessionStore: SessionStore {
    private var session: StoredSession?
    private var saves = 0

    init(session: StoredSession? = nil) {
        self.session = session
    }

    func load() async throws -> StoredSession? { session }

    func save(_ session: StoredSession) async throws {
        self.session = session
        saves += 1
    }

    func delete() async throws {
        session = nil
    }

    func saveCount() -> Int { saves }
}

private enum SessionStoreTestError: Error, Equatable {
    case writeFailed
}

private actor FailingSessionStore: SessionStore {
    func load() async throws -> StoredSession? { nil }
    func save(_ session: StoredSession) async throws { throw SessionStoreTestError.writeFailed }
    func delete() async throws {}
}
