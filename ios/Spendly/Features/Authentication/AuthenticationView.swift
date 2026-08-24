import AuthenticationServices
import GoogleSignIn
import GoogleSignInSwift
import SwiftUI

struct AuthenticationView: View {
    @Bindable var model: AuthenticationModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Spendly")
                    .font(.largeTitle.bold())
                Text("Your purchases, clear and shared.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                AppleAuthenticationButton {
                    Task { await model.signIn(with: .apple) }
                }
                .frame(height: 44)
                .disabled(model.isSigningIn)

                GoogleSignInButton {
                    Task { await model.signIn(with: .google) }
                }
                .frame(minHeight: 44)
                .disabled(model.isSigningIn)

                if model.isSigningIn {
                    ProgressView()
                        .accessibilityLabel("Signing in")
                }

                if let failure = model.failure {
                    Text(message(for: failure))
                        .font(.footnote)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(24)
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
    }

    private func message(for failure: AppFailure) -> String {
        switch failure {
        case .network, .offline:
            "Check your connection and try again."
        case .unauthenticated:
            "Sign-in could not be verified. Please try again."
        default:
            "Something went wrong. Please try again."
        }
    }
}

private struct AppleAuthenticationButton: UIViewRepresentable {
    @Environment(\.isEnabled) private var isEnabled
    let action: @MainActor () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(action: action)
    }

    func makeUIView(context: Context) -> ASAuthorizationAppleIDButton {
        let button = ASAuthorizationAppleIDButton(type: .continue, style: .black)
        button.cornerRadius = 8
        button.addTarget(context.coordinator, action: #selector(Coordinator.invoke), for: .touchUpInside)
        return button
    }

    func updateUIView(_ button: ASAuthorizationAppleIDButton, context: Context) {
        button.isEnabled = isEnabled
        button.alpha = isEnabled ? 1 : 0.5
    }

    @MainActor
    final class Coordinator: NSObject {
        private let action: @MainActor () -> Void

        init(action: @escaping @MainActor () -> Void) {
            self.action = action
        }

        @objc func invoke() {
            action()
        }
    }
}

private extension AuthenticationModel {
    var isSigningIn: Bool {
        if case .signingIn = state {
            return true
        }
        return false
    }
}
