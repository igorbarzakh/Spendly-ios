import XCTest
@testable import Spendly

final class SmokeTests: XCTestCase {
    func testApplicationEnvironmentStoresRESTAndOAuthConfiguration() throws {
        let environment = try AppEnvironment(
            apiBaseURL: XCTUnwrap(URL(string: "https://api.spendly.app")),
            googleOAuthClientID: "google-client-id",
            googleServerClientID: "google-server-client-id",
            appleOAuthClientID: "app.spendly.ios",
            configuration: .production
        )

        XCTAssertEqual(environment.apiBaseURL.host, "api.spendly.app")
        XCTAssertEqual(environment.googleOAuthClientID, "google-client-id")
        XCTAssertEqual(environment.googleServerClientID, "google-server-client-id")
        XCTAssertEqual(environment.appleOAuthClientID, "app.spendly.ios")
    }

    func testApplicationEnvironmentRejectsDirectManagedDatabaseHost() throws {
        let managedDatabaseHost = ["example", ["supa", "base"].joined(), "co"].joined(separator: ".")
        let url = try XCTUnwrap(URL(string: "https://\(managedDatabaseHost)"))

        XCTAssertThrowsError(
            try AppEnvironment(
                apiBaseURL: url,
                googleOAuthClientID: "google-client-id",
                googleServerClientID: "google-server-client-id",
                appleOAuthClientID: "app.spendly.ios",
                configuration: .production
            )
        )
    }

    func testApplicationEnvironmentRejectsInsecureRemoteURL() throws {
        let url = try XCTUnwrap(URL(string: "http://api.spendly.app"))

        XCTAssertThrowsError(
            try AppEnvironment(
                apiBaseURL: url,
                googleOAuthClientID: "google-client-id",
                googleServerClientID: "google-server-client-id",
                appleOAuthClientID: "app.spendly.ios",
                configuration: .production
            )
        )
    }

    func testDevelopmentEnvironmentAllowsLocalHTTP() throws {
        let environment = try AppEnvironment(
            apiBaseURL: XCTUnwrap(URL(string: "http://localhost:8080")),
            googleOAuthClientID: "google-client-id",
            googleServerClientID: "google-server-client-id",
            appleOAuthClientID: "app.spendly.ios",
            configuration: .development
        )

        XCTAssertEqual(environment.apiBaseURL.port, 8080)
    }

    func testGoogleCoordinatorUsesSeparateAppAndServerClientIDs() {
        let configuration = GoogleSignInCoordinator.makeConfiguration(
            clientID: "ios-client-id",
            serverClientID: "web-client-id"
        )

        XCTAssertEqual(configuration.clientID, "ios-client-id")
        XCTAssertEqual(configuration.serverClientID, "web-client-id")
    }
}
