import CryptoKit
import Foundation
import XCTest
@testable import Spendly

@MainActor
final class AuthenticationModelTests: XCTestCase {
    func testRestorePublishesExistingSession() async {
        let session = UserSession(userID: UserID(rawValue: UUID()))
        let repository = AuthenticationRepositoryStub(currentSession: session)
        let model = makeModel(repository: repository)

        await model.restore()

        XCTAssertEqual(model.state, .authenticated(session))
    }

    func testProviderNonceReachesSessionRepositoryUnchanged() async {
        let session = UserSession(userID: UserID(rawValue: UUID()))
        let repository = AuthenticationRepositoryStub(signInSession: session)
        let credential = ProviderCredential(provider: .apple, idToken: "apple-token", nonce: "raw-nonce")
        let apple = AuthenticationCoordinatorStub(provider: .apple, result: .success(credential))
        let model = makeModel(repository: repository, apple: apple)

        await model.signIn(with: .apple)

        let receivedCredential = await repository.lastCredential()
        XCTAssertEqual(receivedCredential, credential)
        XCTAssertEqual(model.state, .authenticated(session))
    }

    func testCancelledProviderUIReturnsToSignedOutStateWithoutError() async {
        let repository = AuthenticationRepositoryStub()
        let google = AuthenticationCoordinatorStub(
            provider: .google,
            result: .failure(AuthenticationProviderError.cancelled)
        )
        let model = makeModel(repository: repository, google: google)

        await model.signIn(with: .google)

        XCTAssertEqual(model.state, .signedOut)
        XCTAssertNil(model.failure)
        let receivedCredential = await repository.lastCredential()
        XCTAssertNil(receivedCredential)
    }

    func testOnlyAppleAndGoogleProvidersAreExposed() {
        XCTAssertEqual(AuthenticationProvider.allCases, [.apple, .google])
    }

    func testAppleNonceContainsSHA256OfRawValue() throws {
        let nonce = try AppleNonce.generate()
        let expectedHash = SHA256.hash(data: Data(nonce.rawValue.utf8))
            .map { String(format: "%02x", $0) }
            .joined()

        XCTAssertFalse(nonce.rawValue.isEmpty)
        XCTAssertEqual(nonce.hashedValue, expectedHash)
        XCTAssertNotEqual(nonce.rawValue, nonce.hashedValue)
    }

    private func makeModel(
        repository: AuthenticationRepositoryStub,
        apple: AuthenticationCoordinatorStub? = nil,
        google: AuthenticationCoordinatorStub? = nil
    ) -> AuthenticationModel {
        AuthenticationModel(
            sessionRepository: repository,
            appleCoordinator: apple ?? AuthenticationCoordinatorStub(provider: .apple),
            googleCoordinator: google ?? AuthenticationCoordinatorStub(provider: .google)
        )
    }
}

private actor AuthenticationRepositoryStub: SessionRepository {
    private let restoredSession: UserSession?
    private let resultSession: UserSession?
    private var credential: ProviderCredential?

    init(currentSession: UserSession? = nil, signInSession: UserSession? = nil) {
        self.restoredSession = currentSession
        self.resultSession = signInSession
    }

    func currentSession() async throws -> UserSession? { restoredSession }

    func signIn(with credential: ProviderCredential) async throws -> UserSession {
        self.credential = credential
        return resultSession ?? UserSession(userID: UserID(rawValue: UUID()))
    }

    func accessToken() async throws -> String? { nil }

    func signOut() async throws {}

    func lastCredential() -> ProviderCredential? { credential }
}

@MainActor
private final class AuthenticationCoordinatorStub: AuthenticationCoordinator {
    let provider: AuthenticationProvider
    private let result: Result<ProviderCredential, Error>

    init(
        provider: AuthenticationProvider,
        result: Result<ProviderCredential, Error>? = nil
    ) {
        self.provider = provider
        self.result = result ?? .success(
            ProviderCredential(provider: provider, idToken: "token", nonce: "nonce")
        )
    }

    func credential() async throws -> ProviderCredential {
        try result.get()
    }
}
