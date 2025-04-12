//
//  MigrationPlan.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//

import SwiftData

enum LocalSchemaMigrationPlan: @preconcurrency SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LocalSchemaV1.self, LocalSchemaV2.self]
    }
    @MainActor static var stages: [MigrationStage] {
        [migrateV1toV2]
    }
    
    @MainActor static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LocalSchemaV1.self,
        toVersion: LocalSchemaV2.self
    )
}
