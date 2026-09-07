import SwiftUI

@main
struct SpendlyApp: App {
    private let composition: Result<AppComposition, Error>

    init() {
        composition = Result { try AppComposition(environment: AppEnvironment.load()) }
    }

    var body: some Scene {
        WindowGroup {
            switch composition {
            case let .success(composition):
                SpendlyRootView(composition: composition)
            case .failure:
                ContentUnavailableView(
                    "Configuration error",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Spendly could not load its environment settings.")
                )
            }
        }
    }
}

private struct SpendlyRootView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: AuthenticationModel
    private let composition: AppComposition

    init(composition: AppComposition) {
        _model = State(initialValue: composition.authenticationModel)
        self.composition = composition
    }

    var body: some View {
        SwiftUI.Group {
            switch model.state {
            case .restoring:
                ProgressView("Restoring session")
            case .signedOut, .signingIn:
                AuthenticationView(model: model)
            case let .authenticated(session):
                ExpensesHomeView(
                    purchaseRepository: composition.purchaseRepository,
                    expenseContext: .personal(session.userID),
                    onSignOut: { Task { await model.signOut() } }
                )
            }
        }
        .task {
            await model.restore()
        }
        .task(id: authenticatedUserID) {
            guard let authenticatedUserID else { return }
            await composition.synchronize(for: authenticatedUserID)
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, let userID = authenticatedUserID else { return }
            Task { await composition.synchronize(for: userID) }
        }
    }

    private var authenticatedUserID: UserID? {
        guard case let .authenticated(session) = model.state else { return nil }
        return session.userID
    }
}
