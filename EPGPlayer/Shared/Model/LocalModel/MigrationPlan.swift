//
//  MigrationPlan.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/12.
//
//  SPDX-License-Identifier: MPL-2.0

import SwiftData

enum LocalSchemaMigrationPlan: @preconcurrency SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [LocalSchemaV1.self, LocalSchemaV2.self, LocalSchemaV3.self, LocalSchemaV4.self]
    }
    @MainActor static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4]
    }
    
    @MainActor static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: LocalSchemaV1.self,
        toVersion: LocalSchemaV2.self
    )
    
    @MainActor static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: LocalSchemaV2.self,
        toVersion: LocalSchemaV3.self
    )
    
    @MainActor static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: LocalSchemaV3.self,
        toVersion: LocalSchemaV4.self
    )
}
