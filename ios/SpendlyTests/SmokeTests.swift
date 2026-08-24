import XCTest
@testable import Spendly

final class SmokeTests: XCTestCase {
    func testApplicationEnvironmentUsesProxyURL() throws {
        let environment = try AppEnvironment(
            apiBaseURL: XCTUnwrap(URL(string: "https://api.spendly.app")),
            publishableKey: "test-key"
        )

        XCTAssertEqual(environment.apiBaseURL.host, "api.spendly.app")
    }

    func testApplicationEnvironmentRejectsDirectSupabaseHost() throws {
        let url = try XCTUnwrap(URL(string: "https://example.supabase.co"))

        XCTAssertThrowsError(
            try AppEnvironment(apiBaseURL: url, publishableKey: "test-key")
        )
    }

    func testApplicationEnvironmentRejectsInsecureRemoteURL() throws {
        let url = try XCTUnwrap(URL(string: "http://api.spendly.app"))

        XCTAssertThrowsError(
            try AppEnvironment(apiBaseURL: url, publishableKey: "test-key")
        )
    }
}
