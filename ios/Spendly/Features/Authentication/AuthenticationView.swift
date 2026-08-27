import GoogleSignIn
import SwiftUI

enum AuthenticationViewContent {
    static let title = "Welcome to Spendly"
    static let subtitle = "Track. Share. Stay."
    static let googleButtonTitle = "Continue with Google"
}

enum AuthenticationButtonMetrics {
    static let height: CGFloat = 44
    static let cornerRadius: CGFloat = 8
    static let iconSize: CGFloat = 20
    static let iconTitleSpacing: CGFloat = 8
    static let borderWidth: CGFloat = 1
}

enum AuthenticationProviderLogoName {
    static let google = "GoogleLogo"
}

enum AuthenticationProviderButtonKind: Equatable, Hashable {
    case google
}

enum AuthenticationProviderButtonOrder {
    static let loginScreen: [AuthenticationProviderButtonKind] = [.google]
}

struct AuthenticationView: View {
    @Bindable var model: AuthenticationModel

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            WelcomeHeader()

            Spacer()

            VStack(spacing: 14) {
                ForEach(AuthenticationProviderButtonOrder.loginScreen, id: \.self) { provider in
                    authenticationButton(for: provider)
                        .disabled(model.isSigningIn)
                }

                if model.isSigningIn {
                    ProgressView()
                        .accessibilityLabel("Signing in")
                }

                if let failure = model.failure {
                    Text(message(for: failure))
                        .font(.footnote)
                        .foregroundStyle(AppColor.danger)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .padding(24)
        .background(AppColor.white)
        .onOpenURL { url in
            GIDSignIn.sharedInstance.handle(url)
        }
    }

    @ViewBuilder
    private func authenticationButton(for provider: AuthenticationProviderButtonKind) -> some View {
        switch provider {
        case .google:
            GoogleAuthenticationButton {
                Task { await model.signIn(with: .google) }
            }
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

private struct WelcomeHeader: View {
    var body: some View {
        VStack(spacing: 14) {
            Image("SpendlyLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 56, height: 56)
                .accessibilityHidden(true)

            VStack(spacing: 6) {
                Text(AuthenticationViewContent.title)
                    .font(.title2.bold())
                    .foregroundStyle(AppColor.black)
                    .multilineTextAlignment(.center)

                Text(AuthenticationViewContent.subtitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
    }
}

private struct GoogleAuthenticationButton: View {
    @Environment(\.isEnabled) private var isEnabled
    let action: @MainActor () -> Void

    var body: some View {
        AuthenticationProviderButton(
            title: AuthenticationViewContent.googleButtonTitle,
            logoName: AuthenticationProviderLogoName.google,
            foregroundColor: AppColor.black,
            backgroundColor: AppColor.white,
            borderColor: AppColor.border,
            action: action
        )
        .opacity(isEnabled ? 1 : 0.5)
        .accessibilityLabel(AuthenticationViewContent.googleButtonTitle)
    }
}

private struct AuthenticationProviderButton: View {
    let title: String
    let logoName: String
    let foregroundColor: Color
    let backgroundColor: Color
    let borderColor: Color
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: AuthenticationButtonMetrics.iconTitleSpacing) {
                logoView
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(foregroundColor)
            }
            .frame(maxWidth: .infinity)
            .frame(height: AuthenticationButtonMetrics.height)
            .padding(.horizontal, 18)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AuthenticationButtonMetrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AuthenticationButtonMetrics.cornerRadius, style: .continuous)
                    .strokeBorder(borderColor, lineWidth: AuthenticationButtonMetrics.borderWidth)
            )
            .contentShape(RoundedRectangle(cornerRadius: AuthenticationButtonMetrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var logoView: some View {
        Image(logoName)
            .resizable()
            .scaledToFit()
            .frame(
                width: AuthenticationButtonMetrics.iconSize,
                height: AuthenticationButtonMetrics.iconSize
            )
            .accessibilityHidden(true)
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
