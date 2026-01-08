import Foundation
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let service = "de.godsapp.ntfy"

    private init() {}

    // MARK: - Save

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? delete(key: key)

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    func load(key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }
            return string
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.loadFailed(status)
        }
    }

    // MARK: - Delete

    func delete(key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }

    // MARK: - Convenience Methods

    func saveCredentials(serverURL: String, username: String, password: String) throws {
        try save(key: "\(serverURL)-username", value: username)
        try save(key: "\(serverURL)-password", value: password)
    }

    func loadCredentials(serverURL: String) -> (username: String, password: String)? {
        guard let username = try? load(key: "\(serverURL)-username"),
              let password = try? load(key: "\(serverURL)-password") else {
            return nil
        }
        return (username, password)
    }

    func deleteCredentials(serverURL: String) throws {
        try delete(key: "\(serverURL)-username")
        try delete(key: "\(serverURL)-password")
    }

    func saveToken(serverURL: String, token: String) throws {
        try save(key: "\(serverURL)-token", value: token)
    }

    func loadToken(serverURL: String) -> String? {
        try? load(key: "\(serverURL)-token")
    }

    func deleteToken(serverURL: String) throws {
        try delete(key: "\(serverURL)-token")
    }

    // MARK: - Clear All

    func clearAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]

        let status = SecItemDelete(query as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.deleteFailed(status)
        }
    }
}

enum KeychainError: LocalizedError {
    case encodingFailed
    case decodingFailed
    case saveFailed(OSStatus)
    case loadFailed(OSStatus)
    case deleteFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .encodingFailed:
            return "Fehler beim Kodieren der Daten"
        case .decodingFailed:
            return "Fehler beim Dekodieren der Daten"
        case .saveFailed(let status):
            return "Fehler beim Speichern (Code: \(status))"
        case .loadFailed(let status):
            return "Fehler beim Laden (Code: \(status))"
        case .deleteFailed(let status):
            return "Fehler beim Löschen (Code: \(status))"
        }
    }
}
