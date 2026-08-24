import Foundation

protocol HTTPTransport: Sendable {
    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

struct URLSessionTransport: HTTPTransport, @unchecked Sendable {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        return (data, httpResponse)
    }
}

protocol APISleeper: Sendable {
    func sleep(for delay: TimeInterval) async throws
}

struct SystemAPISleeper: APISleeper {
    func sleep(for delay: TimeInterval) async throws {
        try await Task.sleep(for: .seconds(delay))
    }
}

enum HTTPMethod: String, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case patch = "PATCH"
    case delete = "DELETE"

    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete:
            true
        case .post, .patch:
            false
        }
    }
}

struct APIEndpoint<Response: Decodable & Sendable>: Sendable {
    let path: String
    let method: HTTPMethod
    let queryItems: [URLQueryItem]
    let headers: [String: String]
    let body: Data?
    let requiresAuthorization: Bool

    static func get(
        _ path: String,
        queryItems: [URLQueryItem] = [],
        requiresAuthorization: Bool = false,
        headers: [String: String] = [:]
    ) -> Self {
        Self(
            path: path,
            method: .get,
            queryItems: queryItems,
            headers: headers,
            body: nil,
            requiresAuthorization: requiresAuthorization
        )
    }

    static func post<Body: Encodable & Sendable>(
        _ path: String,
        body: Body,
        requiresAuthorization: Bool = false,
        headers: [String: String] = [:]
    ) throws -> Self {
        Self(
            path: path,
            method: .post,
            queryItems: [],
            headers: headers,
            body: try APIClient.makeEncoder().encode(body),
            requiresAuthorization: requiresAuthorization
        )
    }
}

actor APIClient {
    typealias AuthorizationProvider = @Sendable () async -> String?
    typealias AuthorizationRefresher = @Sendable () async throws -> String?
    typealias RequestIDProvider = @Sendable () -> String

    private let baseURL: URL
    private let transport: any HTTPTransport
    private let sleeper: any APISleeper
    private let authorization: AuthorizationProvider
    private let refreshAuthorization: AuthorizationRefresher
    private let requestID: RequestIDProvider
    private let decoder: JSONDecoder

    init(
        baseURL: URL,
        transport: any HTTPTransport = URLSessionTransport(),
        sleeper: any APISleeper = SystemAPISleeper(),
        authorization: @escaping AuthorizationProvider = { nil },
        refreshAuthorization: @escaping AuthorizationRefresher = { nil },
        requestID: @escaping RequestIDProvider = { UUID().uuidString }
    ) {
        self.baseURL = baseURL
        self.transport = transport
        self.sleeper = sleeper
        self.authorization = authorization
        self.refreshAuthorization = refreshAuthorization
        self.requestID = requestID
        self.decoder = Self.makeDecoder()
    }

    func send<Response>(_ endpoint: APIEndpoint<Response>) async throws -> Response {
        let token = endpoint.requiresAuthorization ? await authorization() : nil
        return try await send(endpoint, token: token, didRefresh: false, retryCount: 0)
    }

    private func send<Response>(
        _ endpoint: APIEndpoint<Response>,
        token: String?,
        didRefresh: Bool,
        retryCount: Int
    ) async throws -> Response {
        let request = try makeRequest(for: endpoint, token: token)
        let data: Data
        let response: HTTPURLResponse

        do {
            (data, response) = try await transport.data(for: request)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as APIError {
            throw error
        } catch {
            guard endpoint.method.isIdempotent, retryCount == 0 else {
                throw APIError.network
            }
            try await sleeper.sleep(for: 0.25)
            return try await send(endpoint, token: token, didRefresh: didRefresh, retryCount: retryCount + 1)
        }

        if response.statusCode == 401,
           endpoint.requiresAuthorization,
           !didRefresh,
           let refreshedToken = try await refreshAuthorization() {
            return try await send(endpoint, token: refreshedToken, didRefresh: true, retryCount: retryCount)
        }

        if (500..<600).contains(response.statusCode),
           endpoint.method.isIdempotent,
           retryCount == 0 {
            try await sleeper.sleep(for: 0.25)
            return try await send(endpoint, token: token, didRefresh: didRefresh, retryCount: retryCount + 1)
        }

        guard (200..<300).contains(response.statusCode) else {
            throw decodeServerError(from: data, statusCode: response.statusCode)
        }

        do {
            let responseData = data.isEmpty ? Data("{}".utf8) : data
            return try decoder.decode(Response.self, from: responseData)
        } catch {
            throw APIError.decoding
        }
    }

    private func makeRequest<Response>(for endpoint: APIEndpoint<Response>, token: String?) throws -> URLRequest {
        let relativePath = endpoint.path.drop(while: { $0 == "/" })
        let endpointURL = baseURL.appending(path: String(relativePath))
        guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
            throw APIError.invalidURL
        }
        if !endpoint.queryItems.isEmpty {
            components.queryItems = endpoint.queryItems
        }
        guard let url = components.url else {
            throw APIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = endpoint.method.rawValue
        request.httpBody = endpoint.body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(requestID(), forHTTPHeaderField: "X-Request-ID")
        if endpoint.body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        for (name, value) in endpoint.headers {
            request.setValue(value, forHTTPHeaderField: name)
        }
        return request
    }

    private func decodeServerError(from data: Data, statusCode: Int) -> APIError {
        guard let envelope = try? decoder.decode(APIErrorEnvelopeDTO.self, from: data) else {
            return .server(
                statusCode: statusCode,
                code: "unknown",
                message: HTTPURLResponse.localizedString(forStatusCode: statusCode),
                requestID: ""
            )
        }
        return .server(
            statusCode: statusCode,
            code: envelope.error.code,
            message: envelope.error.message,
            requestID: envelope.error.requestId
        )
    }

    nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            guard let date = standard.date(from: value) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Invalid ISO 8601 date"
                )
            }
            return date
        }
        return decoder
    }
}
