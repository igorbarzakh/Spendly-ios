import Foundation

enum AppFailure: Error, Sendable, Equatable {
    case unauthenticated
    case forbidden
    case validation(fields: [String: String])
    case notFound
    case conflict
    case rateLimited(retryAfter: TimeInterval?)
    case offline
    case network
    case server
    case unknown
}

