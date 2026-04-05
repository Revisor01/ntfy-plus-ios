import SwiftData

// MARK: - Current Schema
// Alle neuen Properties haben Default-Werte, daher keine Migration nötig.
// SwiftData handled das automatisch bei neuen Properties mit Defaults.

enum NtfySchema: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}
