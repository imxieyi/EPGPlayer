//
//  LocalFileManager.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/11.
//

import Foundation

class LocalFileManager {
    @MainActor static let shared = LocalFileManager()
    private init() {}
    
    private(set) var filesDir: URL!
    
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
}
