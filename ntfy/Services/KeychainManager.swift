import Foundation
import Security

final class KeychainManager: Sendable {
    static let shared = KeychainManager()

    private let service = "de.godsapp.ntfy"

    /// Explizite, mit der NotificationServiceExtension geteilte Keychain-Access-Group
    /// ("<TeamID>.de.godsapp.ntfy"). Der Team-Prefix kommt zur Laufzeit aus dem
    /// Info.plist-Key `AppIdentifierPrefix` (= `$(AppIdentifierPrefix)`, inkl. Punkt).
    /// Fehlt der Key (z.B. unsignierter Simulator-Build), wird ohne Access-Group
    /// gearbeitet — dann landet alles wie bisher in der Default-Group der App.
    ///
    /// Bestehende Items wurden ohne Access-Group gespeichert und liegen damit in der
    /// Default-Group = erster Eintrag von `keychain-access-groups` = genau diese Group.
    /// Sie bleiben also mit expliziter Group lesbar; zur Sicherheit faellt `load`
    /// trotzdem auf eine Abfrage ohne Group zurueck.
    let accessGroup: String?

    private init() {
        if let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
           !prefix.isEmpty,
           !prefix.contains("$(") {
            let normalizedPrefix = prefix.hasSuffix(".") ? prefix : prefix + "."
            accessGroup = normalizedPrefix + "de.godsapp.ntfy"
        } else {
            accessGroup = nil
        }
    }

    // MARK: - Save

    func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }

        // Delete existing item first
        try? delete(key: key)

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var status = SecItemAdd(query as CFDictionary, nil)

        // Sicherheitsnetz: passt die Group nicht zu den Entitlements (falscher Prefix),
        // lieber ohne explizite Group speichern als den Wert zu verlieren.
        if status == errSecMissingEntitlement, accessGroup != nil {
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            status = SecItemAdd(query as CFDictionary, nil)
        }

        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    // MARK: - Load

    func load(key: String) throws -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup = self.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        var status = SecItemCopyMatching(query as CFDictionary, &result)
        var foundOutsideAccessGroup = false

        // Fallback: Altbestand ausserhalb der expliziten Group (sollte nicht vorkommen,
        // da die Default-Group identisch ist) — ohne Group sucht iOS in allen Groups der App.
        if status == errSecItemNotFound, accessGroup != nil {
            query.removeValue(forKey: kSecAttrAccessGroup as String)
            result = nil
            status = SecItemCopyMatching(query as CFDictionary, &result)
            foundOutsideAccessGroup = (status == errSecSuccess)
        }

        switch status {
        case errSecSuccess:
            guard let attributes = result as? [String: Any],
                  let data = attributes[kSecValueData as String] as? Data,
                  let string = String(data: data, encoding: .utf8) else {
                throw KeychainError.decodingFailed
            }

            // Item lag nicht in der geteilten Group → per SecItemUpdate dorthin umziehen,
            // damit die NotificationServiceExtension es lesen kann. Update statt
            // Delete+Add: schlaegt es fehl, bleibt das Item unveraendert erhalten.
            if foundOutsideAccessGroup, let accessGroup = self.accessGroup {
                let moveQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key
                ]
                let moveAttributes: [String: Any] = [
                    kSecAttrAccessGroup as String: accessGroup,
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ]
                _ = SecItemUpdate(moveQuery as CFDictionary, moveAttributes as CFDictionary)
                return string
            }

            // Transparente Migration: Items mit dem alten Accessibility-Attribut
            // (kSecAttrAccessibleAfterFirstUnlock, ohne ThisDeviceOnly) auf das
            // neue Attribut umschreiben. Ein Fehlschlag der Migration darf den
            // Lesevorgang nicht scheitern lassen — der Wert wird trotzdem zurueckgegeben.
            let currentAccessible = attributes[kSecAttrAccessible as String] as? String
            let targetAccessible = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly as String
            if currentAccessible != targetAccessible {
                let updateQuery: [String: Any] = [
                    kSecClass as String: kSecClassGenericPassword,
                    kSecAttrService as String: service,
                    kSecAttrAccount as String: key
                ]
                let updateAttributes: [String: Any] = [
                    kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
                ]
                _ = SecItemUpdate(updateQuery as CFDictionary, updateAttributes as CFDictionary)
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

    // MARK: - FCM Token

    func saveFCMToken(_ token: String) throws {
        try save(key: "fcmToken", value: token)
    }

    func loadFCMToken() -> String? {
        try? load(key: "fcmToken")
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
