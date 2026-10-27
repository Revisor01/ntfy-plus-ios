import SwiftData

// MARK: - Current Schema
// Neue Properties haben Default-Werte, daher keine Migration.

enum NtfySchema: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}
