import SwiftData

// MARK: - Schema V1
// Eingefroren als Baseline vor allen @Model-Property-Änderungen in Phase 2+.
// Null Migration-Stages = das aktuelle On-Disk-Format IST V1.

enum NtfySchemaV1: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}

// MARK: - Schema V2
// Erweitert V1 mit denormalisierten Performance-Properties auf Topic:
// unreadCount, lastMessagePreview, lastMessagePriority, lastMessageIconURL

enum NtfySchemaV2: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(2, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}

// MARK: - Schema V3
// Erweitert V2 mit isStarred: Bool = false auf StoredMessage (Phase 4: Star Feature).
// Lightweight Migration — kein Custom-Code nötig da Default-Wert false.
// Eingefroren als Baseline vor Phase 5.

enum NtfySchemaV3: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(3, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}

// MARK: - Schema V4
// Erweitert V3 mit customSoundName: String? und defaultPriority: Int = 3 auf Topic (Phase 5: Notification Customization).
// Lightweight Migration — kein Custom-Code nötig da Optional/Default-Werte.

enum NtfySchemaV4: VersionedSchema {
    nonisolated(unsafe) static var versionIdentifier = Schema.Version(4, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}

// MARK: - Migration Plan

enum NtfyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NtfySchemaV1.self, NtfySchemaV2.self, NtfySchemaV3.self, NtfySchemaV4.self] }
    static var stages: [MigrationStage] { [migrateV1toV2, migrateV2toV3, migrateV3toV4] }

    static let migrateV1toV2 = MigrationStage.custom(
        fromVersion: NtfySchemaV1.self,
        toVersion: NtfySchemaV2.self,
        willMigrate: nil,
        didMigrate: { context in
            let topics = (try? context.fetch(FetchDescriptor<Topic>())) ?? []

            for topic in topics {
                // unreadCount: Ungelesene Nachrichten zaehlen
                topic.unreadCount = topic.messages?.filter { !$0.isRead }.count ?? 0

                // Neueste Message nach time DESC sortiert
                if let latestMessage = topic.messages?.max(by: { $0.time < $1.time }) {
                    topic.lastMessagePreview = latestMessage.message ?? latestMessage.title
                    topic.lastMessagePriority = latestMessage.priority
                    topic.lastMessageIconURL = latestMessage.iconURL
                } else {
                    topic.lastMessagePreview = nil
                    topic.lastMessagePriority = 3
                    topic.lastMessageIconURL = nil
                }
            }

            try? context.save()
        }
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: NtfySchemaV2.self,
        toVersion: NtfySchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: NtfySchemaV3.self,
        toVersion: NtfySchemaV4.self
    )
}
