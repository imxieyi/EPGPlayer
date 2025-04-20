//
//  LocalFileManager.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//
//  SPDX-License-Identifier: MPL-2.0

import Combine
import Foundation
import SwiftData

class LocalFileManager {
    @MainActor static let shared = LocalFileManager()
    
    private(set) var filesDir: URL!
    var container: ModelContainer?
    
    private init() {}
    
    func initialize() throws {
        let documentDir = try FileManager.default.url(for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
        filesDir = documentDir.appending(path: "files")
        try FileManager.default.createDirectory(at: filesDir, withIntermediateDirectories: true)
    }
    
    func saveData(name: String, data: Data) throws {
        try data.write(to: filesDir.appending(path: name))
    }
    
    func moveFile(name: String, url: URL) throws {
        try FileManager.default.moveItem(at: url, to: filesDir.appending(path: name))
    }
    
    func deleteFile(name: String) throws {
        try FileManager.default.removeItem(at: filesDir.appending(path: name))
    }
    
    func totalSize() throws -> Int {
        return try FileManager.default.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil).reduce(0) { size, url in
            size + (try url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize ?? 0)
        }
    }
    
    func fixFilesAvailability() {
        guard let container else { return }
        Task(priority: .background) { @MainActor [filesDir] in
            do {
                let unavailableFiles = try container.mainContext.fetch(FetchDescriptor<LocalFile>(predicate: #Predicate { !$0.available }))
                for file in unavailableFiles {
                    if FileManager.default.fileExists(atPath: filesDir!.appending(path: file.id.uuidString).path()) {
                        file.available = true
                    }
                }
                print("Fixed availablility for \(unavailableFiles.count) files")
            } catch let error {
                print("Failed to fix files availablility: \(error)")
            }
        }
    }
    
    @MainActor func deleteOrphans() {
        guard let container else { return }
        do {
            let managedFiles = Set(try container.mainContext.fetch(FetchDescriptor<LocalFile>()).map { $0.id.uuidString })
            let contents = try FileManager.default.contentsOfDirectory(at: filesDir, includingPropertiesForKeys: nil)
            for content in contents {
                let fileName = content.lastPathComponent
                guard !managedFiles.contains(fileName) else { continue }
                do {
                    try FileManager.default.removeItem(at: content)
                } catch let error {
                    print("Failed to delete \(content.path()): \(error.localizedDescription)")
                }
            }
        } catch let error {
            print("Failed to delete orphan files: \(error)")
        }
    }
}
