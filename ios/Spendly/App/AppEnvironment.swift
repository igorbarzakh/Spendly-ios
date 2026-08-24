import Foundation

struct AppEnvironment: Sendable {
    enum Configuration: String, Sendable {
        case development
        case staging
        case production
    }

    enum ValidationError: Error, Equatable {
        case insecureTransport
        case invalidAPIHost
        case missingOAuthClientID
        case missingConfiguration
    }

    static func load(bundle: Bundle = .main) throws -> AppEnvironment {
        func value(_ key: String) throws -> String {
            guard let value = bundle.object(forInfoDictionaryKey: key) as? String,
                  !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ValidationError.missingConfiguration
            }
            return value
        }
        guard let url = URL(string: try value("SPENDLY_API_BASE_URL")),
              let configuration = Configuration(rawValue: try value("SPENDLY_CONFIGURATION")) else {
            throw ValidationError.missingConfiguration
        }
        return try AppEnvironment(
            apiBaseURL: url,
            googleOAuthClientID: value("SPENDLY_GOOGLE_CLIENT_ID"),
            googleServerClientID: value("SPENDLY_GOOGLE_SERVER_CLIENT_ID"),
            appleOAuthClientID: value("SPENDLY_APPLE_CLIENT_ID"),
            configuration: configuration
        )
    }

    let apiBaseURL: URL
    let googleOAuthClientID: String
    let googleServerClientID: String
    let appleOAuthClientID: String
    let configuration: Configuration

    init(
        apiBaseURL: URL,
        googleOAuthClientID: String,
        googleServerClientID: String,
        appleOAuthClientID: String,
        configuration: Configuration
    ) throws {
        if configuration != .development,
           apiBaseURL.scheme?.lowercased() != "https" {
            throw ValidationError.insecureTransport
        }

        let forbiddenManagedDatabaseSuffix = "." + ["supa", "base"].joined() + ".co"
        guard let host = apiBaseURL.host?.lowercased(),
              !host.hasSuffix(forbiddenManagedDatabaseSuffix)
        else {
            throw ValidationError.invalidAPIHost
        }

        guard !googleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !googleServerClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !appleOAuthClientID.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            throw ValidationError.missingOAuthClientID
        }

        self.apiBaseURL = apiBaseURL
        self.googleOAuthClientID = googleOAuthClientID
        self.googleServerClientID = googleServerClientID
        self.appleOAuthClientID = appleOAuthClientID
        self.configuration = configuration
    }
}
