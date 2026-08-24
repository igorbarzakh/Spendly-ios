import Foundation

actor RemoteStatisticsRepository: StatisticsRepository {
    private let apiClient: APIClient
    init(apiClient: APIClient) { self.apiClient = apiClient }

    func statistics(in context: ExpenseContext, interval: DateInterval) async throws -> StatisticsSnapshot {
        do {
            let response = try await apiClient.send(
                APIEndpoint<StatisticsDTO>.get(
                    "/v1/statistics",
                    queryItems: RepositoryMapping.queryItems(context: context, interval: interval),
                    requiresAuthorization: true
                )
            )
            return StatisticsSnapshot(
                totalMinor: response.totalMinor,
                byDay: response.byDay,
                byCategory: response.byCategory
            )
        } catch { throw RepositoryMapping.failure(from: error) }
    }
}
