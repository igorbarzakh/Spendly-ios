import Foundation

enum APIError: Error, Equatable, Sendable {
    case invalidURL
    case invalidResponse
    case encoding
    case decoding
    case network
    case server(statusCode: Int, code: String, message: String, requestID: String)
}
