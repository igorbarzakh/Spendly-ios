import Foundation
import GoogleSignIn
import UIKit

@MainActor
final class GoogleSignInCoordinator: AuthenticationCoordinator {
    let provider: AuthenticationProvider = .google

    private let clientID: String
    private let presentingViewController: @MainActor @Sendable () -> UIViewController?

    init(
        clientID: String,
        presentingViewController: @escaping @MainActor @Sendable () -> UIViewController? = {
            let window = UIApplication.shared.connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap(\.windows)
                .first(where: \.isKeyWindow)
            return window?.rootViewController
        }
    ) {
        self.clientID = clientID
        self.presentingViewController = presentingViewController
    }

    func credential() async throws -> ProviderCredential {
        guard !clientID.isEmpty else {
            throw AuthenticationProviderError.providerFailure
        }
        guard let viewController = presentingViewController() else {
            throw AuthenticationProviderError.presentationUnavailable
        }

        let nonce = try AppleNonce.generate()
        GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)

        return try await withCheckedThrowingContinuation { continuation in
            GIDSignIn.sharedInstance.signIn(
                withPresenting: viewController,
                hint: nil,
                additionalScopes: nil,
                nonce: nonce.rawValue
            ) { result, error in
                if let error = error as NSError? {
                    if error.domain == kGIDSignInErrorDomain,
                       error.code == GIDSignInError.canceled.rawValue {
                        continuation.resume(throwing: AuthenticationProviderError.cancelled)
                    } else {
                        continuation.resume(throwing: AuthenticationProviderError.providerFailure)
                    }
                    return
                }
                guard let idToken = result?.user.idToken?.tokenString else {
                    continuation.resume(throwing: AuthenticationProviderError.invalidCredential)
                    return
                }
                continuation.resume(
                    returning: ProviderCredential(
                        provider: .google,
                        idToken: idToken,
                        nonce: nonce.rawValue
                    )
                )
            }
        }
    }
}
