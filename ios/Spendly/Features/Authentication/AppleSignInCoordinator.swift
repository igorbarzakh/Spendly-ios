import AuthenticationServices
import CryptoKit
import Foundation
import Security
import UIKit

struct AppleNonce: Equatable, Sendable {
    let rawValue: String
    let hashedValue: String

    static func generate(byteCount: Int = 32) throws -> AppleNonce {
        var bytes = [UInt8](repeating: 0, count: byteCount)
        guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else {
            throw AuthenticationProviderError.providerFailure
        }
        let rawValue = bytes.map { String(format: "%02x", $0) }.joined()
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hashedValue = digest.map { String(format: "%02x", $0) }.joined()
        return AppleNonce(rawValue: rawValue, hashedValue: hashedValue)
    }
}

@MainActor
final class AppleSignInCoordinator: NSObject, AuthenticationCoordinator, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
    let provider: AuthenticationProvider = .apple

    private let presentationAnchor: @MainActor @Sendable () -> ASPresentationAnchor?
    private var continuation: CheckedContinuation<ProviderCredential, Error>?
    private var nonce: AppleNonce?
    private var authorizationController: ASAuthorizationController?

    init(
        presentationAnchor: @escaping @MainActor @Sendable () -> ASPresentationAnchor? = {
            UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
        }
    ) {
        self.presentationAnchor = presentationAnchor
    }

    func credential() async throws -> ProviderCredential {
        guard continuation == nil else {
            throw AuthenticationProviderError.providerFailure
        }
        guard presentationAnchor() != nil else {
            throw AuthenticationProviderError.presentationUnavailable
        }

        let nonce = try AppleNonce.generate()
        self.nonce = nonce
        let request = ASAuthorizationAppleIDProvider().createRequest()
        request.requestedScopes = [.fullName, .email]
        request.nonce = nonce.hashedValue

        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            let controller = ASAuthorizationController(authorizationRequests: [request])
            self.authorizationController = controller
            controller.delegate = self
            controller.presentationContextProvider = self
            controller.performRequests()
        }
    }

    func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
        presentationAnchor() ?? ASPresentationAnchor()
    }

    func authorizationController(
        controller: ASAuthorizationController,
        didCompleteWithAuthorization authorization: ASAuthorization
    ) {
        guard let appleCredential = authorization.credential as? ASAuthorizationAppleIDCredential,
              let tokenData = appleCredential.identityToken,
              let idToken = String(data: tokenData, encoding: .utf8),
              let nonce
        else {
            finish(with: .failure(AuthenticationProviderError.invalidCredential))
            return
        }
        finish(
            with: .success(
                ProviderCredential(provider: .apple, idToken: idToken, nonce: nonce.rawValue)
            )
        )
    }

    func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
        if let authorizationError = error as? ASAuthorizationError,
           authorizationError.code == .canceled {
            finish(with: .failure(AuthenticationProviderError.cancelled))
        } else {
            finish(with: .failure(AuthenticationProviderError.providerFailure))
        }
    }

    private func finish(with result: Result<ProviderCredential, Error>) {
        let continuation = self.continuation
        self.continuation = nil
        nonce = nil
        authorizationController = nil
        continuation?.resume(with: result)
    }
}
