// BriefSchema.swift
// Versioned SwiftData schema. Establish explicit versioning now so future
// model changes can ship a SchemaMigrationPlan stage without crashing
// existing users' on-device stores.

import Foundation
import SwiftData

enum BriefSchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { .init(1, 0, 0) }

    static var models: [any PersistentModel.Type] {
        [BriefItem.self]
    }
}

enum BriefMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [BriefSchemaV1.self]
    }

    // Add MigrationStage entries here when introducing BriefSchemaV2, V3, etc.
    // Lightweight migrations cover additive optional fields with defaults;
    // custom stages are needed for renames, type changes, or destructive edits.
    static var stages: [MigrationStage] { [] }
}
