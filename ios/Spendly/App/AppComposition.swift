import Foundation

@MainActor
final class AppComposition {
    let authenticationModel: AuthenticationModel
    let purchaseRepository: any PurchaseRepository
    let groupRepository: any GroupRepository
    let statisticsRepository: any StatisticsRepository
    let syncEngine: SyncEngine
    let store: SwiftDataStore

    init(environment: AppEnvironment) throws {
        self.store = try SwiftDataStore()

        let sessionClient = APIClient(baseURL: environment.apiBaseURL)
        let sessionRepository = RemoteSessionRepository(
            apiClient: sessionClient,
            store: KeychainSessionStore()
        )
        let apiClient = APIClient(
            baseURL: environment.apiBaseURL,
            authorization: { try? await sessionRepository.accessToken() },
            refreshAuthorization: { try await sessionRepository.refreshAccessToken() }
        )
        let mutationTrigger = MutationSyncTrigger(
            currentUserID: { try await sessionRepository.currentSession()?.userID }
        )
        let purchaseRepository = RemotePurchaseRepository(
            apiClient: apiClient,
            cache: store,
            outbox: store,
            currentUserID: { try await sessionRepository.currentSession()?.userID },
            didEnqueue: { await mutationTrigger.trigger() }
        )
        let mutationRepository = RemotePurchaseRepository(apiClient: apiClient, cache: store)
        self.purchaseRepository = purchaseRepository
        self.groupRepository = RemoteGroupRepository(apiClient: apiClient)
        self.statisticsRepository = RemoteStatisticsRepository(apiClient: apiClient)
        self.syncEngine = SyncEngine(
            queue: store,
            executor: RemoteMutationExecutor(repository: mutationRepository),
            source: RemoteSyncPageSource(apiClient: apiClient),
            cache: store
        )
        mutationTrigger.configure(syncEngine)
        self.authenticationModel = AuthenticationModel(
            sessionRepository: sessionRepository,
            appleCoordinator: AppleSignInCoordinator(),
            googleCoordinator: GoogleSignInCoordinator(
                clientID: environment.googleOAuthClientID,
                serverClientID: environment.googleServerClientID
            )
        )
    }

    func synchronize(for userID: UserID) async {
        await syncEngine.synchronize(in: .personal(userID), for: userID)
        guard let groups = try? await groupRepository.groups() else { return }
        for group in groups where group.archivedAt == nil {
            await syncEngine.synchronize(in: .group(group.id), for: userID)
        }
    }
}

@MainActor
private final class MutationSyncTrigger {
    private let currentUserID: @Sendable () async throws -> UserID?
    private var syncEngine: SyncEngine?

    init(currentUserID: @escaping @Sendable () async throws -> UserID?) {
        self.currentUserID = currentUserID
    }

    func configure(_ syncEngine: SyncEngine) {
        self.syncEngine = syncEngine
    }

    func trigger() {
        guard let syncEngine else { return }
        Task {
            guard let userID = try? await currentUserID() else { return }
            await syncEngine.flushMutations(for: userID)
        }
    }
}
