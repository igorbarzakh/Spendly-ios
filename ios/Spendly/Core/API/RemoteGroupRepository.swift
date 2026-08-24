import Foundation

actor RemoteGroupRepository: GroupRepository {
    private let apiClient: APIClient
    private let id: @Sendable () -> UUID

    init(apiClient: APIClient, id: @escaping @Sendable () -> UUID = UUID.init) {
        self.apiClient = apiClient
        self.id = id
    }

    func groups() async throws -> [Group] {
        do {
            let response = try await apiClient.send(
                APIEndpoint<GroupsResponseDTO>.get("/v1/groups", requiresAuthorization: true)
            )
            return response.groups.map(RepositoryMapping.group(from:))
        } catch { throw RepositoryMapping.failure(from: error) }
    }

    func create(name: String) async throws -> Group {
        do {
            let endpoint = try APIEndpoint<GroupDTO>.post(
                "/v1/groups", body: CreateGroupDTO(id: id(), name: name), requiresAuthorization: true
            )
            return RepositoryMapping.group(from: try await apiClient.send(endpoint))
        } catch { throw RepositoryMapping.failure(from: error) }
    }

    func archive(id: GroupID) async throws {
        do {
            let endpoint = try APIEndpoint<EmptyResponseDTO>.request(
                "/v1/groups/\(id.rawValue.uuidString.lowercased())", method: .patch,
                body: ArchiveGroupDTO(archived: true), requiresAuthorization: true
            )
            _ = try await apiClient.send(endpoint)
        } catch { throw RepositoryMapping.failure(from: error) }
    }
}
