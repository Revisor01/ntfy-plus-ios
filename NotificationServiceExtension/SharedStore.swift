import Foundation
import Security

// MARK: - SharedStore
// App-Group-Zugriff der NSE; Keys und Formate sind dupliziert, weil die NSE keinen App-Code importieren kann.

enum SharedStore {
    static let appGroup = "group.de.godsapp.ntfy"
    static let topicServersKey = "topicServers"
    static let pendingDirectoryName = "pending-messages"
    static let mutedTopicKeysKey = "mutedTopicKeys"
    static let mutedTopicNamesKey = "mutedTopicNames"

    static var containerURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroup)
    }

    // MARK: Topic→Server

    /// Alle Server-URLs, auf denen das Topic in der App abonniert ist.
    static func servers(for topic: String) -> [String] {
        let map = UserDefaults(suiteName: appGroup)?.dictionary(forKey: topicServersKey)
        return map?[topic] as? [String] ?? []
    }

    // MARK: Stummgeschaltete Topics

    /// true, wenn das Topic stumm ist; ohne Server zählt der Name nur, wenn alle gleichnamigen Topics stumm sind.
    static func isMuted(topic: String, serverURL: String?) -> Bool {
        guard !topic.isEmpty, let defaults = UserDefaults(suiteName: appGroup) else { return false }
        if let serverURL {
            let keys = defaults.stringArray(forKey: mutedTopicKeysKey) ?? []
            return keys.contains("\(serverURL)|\(topic)")
        }
        let names = defaults.stringArray(forKey: mutedTopicNamesKey) ?? []
        return names.contains(topic)
    }

    // MARK: Badge

    private static var badgeFileURL: URL? {
        containerURL?.appendingPathComponent("badge_count.txt")
    }

    /// Erhoeht den geteilten Badge-Zaehler um 1 und liefert den neuen Wert.
    static func incrementBadgeCount() -> Int {
        var current = 0
        if let url = badgeFileURL,
           let content = try? String(contentsOf: url, encoding: .utf8),
           let count = Int(content.trimmingCharacters(in: .whitespacesAndNewlines)) {
            current = max(0, count)
        }
        let newCount = current + 1
        if let url = badgeFileURL {
            try? String(newCount).write(to: url, atomically: true, encoding: .utf8)
        }
        return newCount
    }

    // MARK: Pending Messages

    /// Legt eine empfangene Nachricht für den Import durch die App ab.
    @discardableResult
    static func writePendingMessage(_ message: [String: Any], serverURL: String?) -> Bool {
        guard let id = message["id"] as? String, !id.isEmpty,
              let containerURL = SharedStore.containerURL else { return false }

        let directory = containerURL.appendingPathComponent(pendingDirectoryName, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        } catch {
            return false
        }

        var envelope: [String: Any] = ["message": message]
        if let serverURL {
            envelope["serverURL"] = serverURL
        }
        guard JSONSerialization.isValidJSONObject(envelope),
              let data = try? JSONSerialization.data(withJSONObject: envelope) else {
            return false
        }

        // Dateiname nur aus sicheren Zeichen (ntfy-IDs sind alphanumerisch)
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let safeId = String(id.unicodeScalars.filter { allowed.contains($0) })
        let fileName = (safeId.isEmpty ? UUID().uuidString : safeId) + ".json"

        do {
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
            return true
        } catch {
            return false
        }
    }
}

// MARK: - SharedKeychain

/// Lesender Keychain-Zugriff der NSE, mit exakt demselben Schema wie KeychainManager.
enum SharedKeychain {
    private static let service = "de.godsapp.ntfy"

    private static var accessGroup: String? {
        guard let prefix = Bundle.main.object(forInfoDictionaryKey: "AppIdentifierPrefix") as? String,
              !prefix.isEmpty,
              !prefix.contains("$(") else {
            return nil
        }
        let normalizedPrefix = prefix.hasSuffix(".") ? prefix : prefix + "."
        return normalizedPrefix + "de.godsapp.ntfy"
    }

    static func loadToken(serverURL: String) -> String? {
        load(key: "\(serverURL)-token")
    }

    static func loadCredentials(serverURL: String) -> (username: String, password: String)? {
        guard let username = load(key: "\(serverURL)-username"),
              let password = load(key: "\(serverURL)-password") else {
            return nil
        }
        return (username, password)
    }

    private static func load(key: String) -> String? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        if let accessGroup = SharedKeychain.accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return string
    }
}
