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

        guard let host = apiBaseURL.host?.lowercased(),
              !host.hasSuffix(".supabase.co")
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
