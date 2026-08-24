protocol GroupRepository: Sendable {
    func groups() async throws -> [Group]
    func create(name: String) async throws -> Group
    func archive(id: GroupID) async throws
}
