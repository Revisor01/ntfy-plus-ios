import SwiftData

// MARK: - Schema V1
// Eingefroren als Baseline vor allen @Model-Property-Änderungen in Phase 2+.
// Null Migration-Stages = das aktuelle On-Disk-Format IST V1.

enum NtfySchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [Topic.self, StoredMessage.self, Server.self, DeletedMessage.self]
    }
}

enum NtfyMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [NtfySchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}
