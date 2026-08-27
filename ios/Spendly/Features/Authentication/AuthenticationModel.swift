import Foundation
import Observation

enum AuthenticationProviderError: Error, Equatable {
    case cancelled
    case invalidCredential
    case presentationUnavailable
    case providerFailure
}

@MainActor
protocol AuthenticationCoordinator: Sendable {
    var provider: AuthenticationProvider { get }
    func credential() async throws -> ProviderCredential
}

@MainActor
@Observable
final class AuthenticationModel {
    enum State: Equatable {
        case restoring
        case signedOut
        case signingIn(AuthenticationProvider)
        case authenticated(UserSession)
    }

    private(set) var state: State = .signedOut
    private(set) var failure: AppFailure?

    private let sessionRepository: any SessionRepository
    private let googleCoordinator: any AuthenticationCoordinator

    init(
        sessionRepository: any SessionRepository,
        googleCoordinator: any AuthenticationCoordinator
    ) {
        self.sessionRepository = sessionRepository
        self.googleCoordinator = googleCoordinator
    }

    func restore() async {
        state = .restoring
        failure = nil
        do {
            if let session = try await sessionRepository.currentSession() {
                state = .authenticated(session)
            } else {
                state = .signedOut
            }
        } catch {
            state = .signedOut
            failure = map(error)
        }
    }

    func signIn(with provider: AuthenticationProvider) async {
        state = .signingIn(provider)
        failure = nil
        do {
            let credential = try await googleCoordinator.credential()
            guard credential.provider == provider else {
                throw AuthenticationProviderError.invalidCredential
            }
            let session = try await sessionRepository.signIn(with: credential)
            state = .authenticated(session)
        } catch AuthenticationProviderError.cancelled {
            state = .signedOut
        } catch is CancellationError {
            state = .signedOut
        } catch {
            state = .signedOut
            failure = map(error)
        }
    }

    func signOut() async {
        do {
            try await sessionRepository.signOut()
            state = .signedOut
            failure = nil
        } catch {
            failure = map(error)
        }
    }

    private func map(_ error: Error) -> AppFailure {
        if let failure = error as? AppFailure {
            return failure
        }
        if let apiError = error as? APIError {
            switch apiError {
            case let .server(statusCode, _, _, _) where statusCode == 401:
                return .unauthenticated
            case .network:
                return .network
            default:
                return .server
            }
        }
        return .unknown
    }
}
