import Foundation
import XCTest
@testable import Spendly

final class APIClientTests: XCTestCase {
    func testDecodesResponseAndBuildsURLRelativeToBaseURL() async throws {
        let transport = RecordingTransport(responses: [
            .response(statusCode: 200, body: #"{"value":"ok"}"#)
        ])
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app/root/")),
            transport: transport
        )

        let response = try await client.send(
            APIEndpoint<TestResponse>.get("v1/test", queryItems: [URLQueryItem(name: "page", value: "1")])
        )

        XCTAssertEqual(response, TestResponse(value: "ok"))
        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.url?.absoluteString, "https://api.spendly.app/root/v1/test?page=1")
    }

    func testURLSessionTransportUsesConfiguredURLProtocol() async throws {
        URLProtocolStub.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Accept"), "application/json")
            return (200, #"{"value":"url-session"}"#)
        }
        defer { URLProtocolStub.handler = nil }

        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        let transport = URLSessionTransport(session: URLSession(configuration: configuration))
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport
        )

        let response = try await client.send(APIEndpoint<TestResponse>.get("/v1/test"))

        XCTAssertEqual(response.value, "url-session")
    }

    func testAddsAuthorizationAndRequestIDHeaders() async throws {
        let transport = RecordingTransport(responses: [
            .response(statusCode: 200, body: #"{"value":"ok"}"#)
        ])
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport,
            authorization: { "access-token" },
            requestID: { "request-123" }
        )

        _ = try await client.send(APIEndpoint<TestResponse>.get("/v1/me", requiresAuthorization: true))

        let recordedRequests = await transport.requests
        let request = try XCTUnwrap(recordedRequests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer access-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Request-ID"), "request-123")
    }

    func testDecodesErrorEnvelopeIncludingRequestID() async throws {
        let transport = RecordingTransport(responses: [
            .response(
                statusCode: 422,
                body: #"{"error":{"code":"validation_failed","message":"Invalid amount","request_id":"req-42"}}"#
            )
        ])
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport
        )

        do {
            _ = try await client.send(APIEndpoint<TestResponse>.get("/v1/test"))
            XCTFail("Expected an API error")
        } catch let error as APIError {
            XCTAssertEqual(
                error,
                .server(statusCode: 422, code: "validation_failed", message: "Invalid amount", requestID: "req-42")
            )
        }
    }

    func testRefreshesAuthorizationOnceAfterUnauthorizedResponse() async throws {
        let transport = RecordingTransport(responses: [
            .response(statusCode: 401, body: #"{"error":{"code":"unauthorized","message":"Expired","request_id":"req-1"}}"#),
            .response(statusCode: 200, body: #"{"value":"ok"}"#)
        ])
        let refresh = RefreshRecorder(token: "new-token")
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport,
            authorization: { "old-token" },
            refreshAuthorization: { try await refresh.refresh() }
        )

        let response = try await client.send(
            APIEndpoint<TestResponse>.get("/v1/me", requiresAuthorization: true)
        )

        XCTAssertEqual(response.value, "ok")
        let refreshCallCount = await refresh.callCount
        XCTAssertEqual(refreshCallCount, 1)
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requests[1].value(forHTTPHeaderField: "Authorization"), "Bearer new-token")
    }

    func testDoesNotRetryRequestWhenAuthorizationRefreshFails() async throws {
        let transport = RecordingTransport(responses: [
            .response(statusCode: 401, body: #"{"error":{"code":"unauthorized","message":"Expired","request_id":"req-1"}}"#),
            .response(statusCode: 401, body: #"{"error":{"code":"unauthorized","message":"Expired","request_id":"req-2"}}"#)
        ])
        let refresh = FailingRefreshRecorder()
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport,
            authorization: { "old-token" },
            refreshAuthorization: { try await refresh.refresh() }
        )

        do {
            _ = try await client.send(
                APIEndpoint<TestResponse>.get("/v1/me", requiresAuthorization: true)
            )
            XCTFail("Expected the refresh failure")
        } catch let error as RefreshFailure {
            XCTAssertEqual(error, .failed)
        }

        let refreshCallCount = await refresh.callCount
        let requestCount = await transport.requests.count
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(requestCount, 1)
    }

    func testRetriesIdempotentRequestAfterTransientFailure() async throws {
        let transport = RecordingTransport(responses: [
            .failure(URLError(.timedOut)),
            .response(statusCode: 200, body: #"{"value":"ok"}"#)
        ])
        let sleeper = SleepRecorder()
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport,
            sleeper: sleeper
        )

        let response = try await client.send(APIEndpoint<TestResponse>.get("/v1/test"))

        XCTAssertEqual(response.value, "ok")
        let requestCount = await transport.requests.count
        let recordedDelays = await sleeper.delays
        XCTAssertEqual(requestCount, 2)
        XCTAssertEqual(recordedDelays, [0.25])
    }

    func testDoesNotRetryNonIdempotentRequest() async throws {
        let transport = RecordingTransport(responses: [
            .failure(URLError(.timedOut))
        ])
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport
        )
        let endpoint = try APIEndpoint<TestResponse>.post(
            "/v1/test",
            body: TestRequest(value: "new")
        )

        do {
            _ = try await client.send(endpoint)
            XCTFail("Expected a network error")
        } catch let error as APIError {
            XCTAssertEqual(error, .network)
        }

        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }

    func testPropagatesCancellationWithoutRetrying() async throws {
        let transport = RecordingTransport(responses: [.failure(CancellationError())])
        let client = APIClient(
            baseURL: try XCTUnwrap(URL(string: "https://api.spendly.app")),
            transport: transport
        )

        do {
            _ = try await client.send(APIEndpoint<TestResponse>.get("/v1/test"))
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected: cancellation remains cancellation for structured concurrency.
        }

        let requestCount = await transport.requests.count
        XCTAssertEqual(requestCount, 1)
    }
}

private struct TestResponse: Codable, Equatable, Sendable {
    let value: String
}

private struct TestRequest: Encodable, Sendable {
    let value: String
}

private actor RecordingTransport: HTTPTransport {
    enum Stub: @unchecked Sendable {
        case response(statusCode: Int, body: String)
        case failure(Error)
    }

    private(set) var requests: [URLRequest] = []
    private var responses: [Stub]

    init(responses: [Stub]) {
        self.responses = responses
    }

    func data(for request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        let response = responses.removeFirst()

        switch response {
        case let .response(statusCode, body):
            let httpResponse = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: nil
            )!
            return (Data(body.utf8), httpResponse)
        case let .failure(error):
            throw error
        }
    }
}

private actor RefreshRecorder {
    private(set) var callCount = 0
    private let token: String

    init(token: String) {
        self.token = token
    }

    func refresh() throws -> String {
        callCount += 1
        return token
    }
}

private enum RefreshFailure: Error, Equatable {
    case failed
}

private actor FailingRefreshRecorder {
    private(set) var callCount = 0

    func refresh() throws -> String? {
        callCount += 1
        throw RefreshFailure.failed
    }
}

private actor SleepRecorder: APISleeper {
    private(set) var delays: [TimeInterval] = []

    func sleep(for delay: TimeInterval) async throws {
        delays.append(delay)
    }
}

private final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, String))?

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }

        do {
            let (statusCode, body) = try handler(request)
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: statusCode,
                httpVersion: nil,
                headerFields: ["Content-Type": "application/json"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8))
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
