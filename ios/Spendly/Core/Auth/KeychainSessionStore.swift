import Foundation
import Security

struct StoredSession: Codable, Equatable, Sendable {
    let userID: UserID
    let accessToken: String
    let refreshToken: String
    let accessExpiresAt: Date
    let refreshExpiresAt: Date
}

protocol SessionStore: Sendable {
    func load() async throws -> StoredSession?
    func save(_ session: StoredSession) async throws
    func delete() async throws
}

enum KeychainSessionStoreError: Error, Equatable {
    case encoding
    case invalidData
    case unexpectedStatus(OSStatus)
}

actor KeychainSessionStore: SessionStore {
    private let service: String
    private let account: String

    init(service: String = "app.spendly.ios.session", account: String = "current") {
        self.service = service
        self.account = account
    }

    func load() throws -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
        guard let data = result as? Data,
              let session = try? JSONDecoder().decode(StoredSession.self, from: data)
        else {
            throw KeychainSessionStoreError.invalidData
        }
        return session
    }

    func save(_ session: StoredSession) throws {
        guard let data = try? JSONEncoder().encode(session) else {
            throw KeychainSessionStoreError.encoding
        }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess {
            return
        }
        guard updateStatus == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(updateStatus)
        }

        var item = baseQuery
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let addStatus = SecItemAdd(item as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw KeychainSessionStoreError.unexpectedStatus(addStatus)
        }
    }

    func delete() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainSessionStoreError.unexpectedStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
            kSecUseDataProtectionKeychain as String: true
        ]
    }
}
