import Foundation

struct AppEnvironment: Sendable {
    enum ValidationError: Error, Equatable {
        case insecureTransport
        case invalidAPIHost
        case missingPublishableKey
    }

    let apiBaseURL: URL
    let publishableKey: String

    init(apiBaseURL: URL, publishableKey: String) throws {
        guard apiBaseURL.scheme?.lowercased() == "https" else {
            throw ValidationError.insecureTransport
        }

        guard let host = apiBaseURL.host?.lowercased(),
              !host.hasSuffix(".supabase.co")
        else {
            throw ValidationError.invalidAPIHost
        }

        guard !publishableKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError.missingPublishableKey
        }

        self.apiBaseURL = apiBaseURL
        self.publishableKey = publishableKey
    }
}

