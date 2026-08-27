import CryptoKit
import Foundation

struct OAuthNonce: Equatable, Sendable {
    let rawValue: String
    let hashedValue: String

    static func generate(length: Int = 32) throws -> OAuthNonce {
        precondition(length > 0)

        let charset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVXYZabcdefghijklmnopqrstuvwxyz-._")
        var randomBytes = [UInt8](repeating: 0, count: length)
        let status = SecRandomCopyBytes(kSecRandomDefault, randomBytes.count, &randomBytes)
        guard status == errSecSuccess else {
            throw AuthenticationProviderError.providerFailure
        }

        let rawValue = String(randomBytes.map { charset[Int($0) % charset.count] })
        let digest = SHA256.hash(data: Data(rawValue.utf8))
        let hashedValue = digest
            .map { String(format: "%02x", $0) }
            .joined()

        return OAuthNonce(rawValue: rawValue, hashedValue: hashedValue)
    }
}
