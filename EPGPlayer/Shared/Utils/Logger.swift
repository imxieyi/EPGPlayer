//
//  Logging.swift
//  EPGPlayer
//
//  Created by Yi Xie on 2025/04/20.
//
//  SPDX-License-Identifier: MPL-2.0

import os
import Foundation
import Logging
import FirebaseCrashlytics

class Logger {
    nonisolated(unsafe) private static var logger: Logging.Logger!
    
    private init() {}
    
    static func initialize(crashlytics: Bool) {
        LoggingSystem.bootstrap { label in
            MyLogHandler(label: label, crashlytics: crashlytics)
        }
        Logger.logger = .init(label: Bundle.main.bundleIdentifier ?? "com.imxieyi.EPGPlayer")
    }
    
    static func debug(_ message: Logging.Logger.Message) {
        log(message, level: .debug)
    }
    
    static func info(_ message: Logging.Logger.Message) {
        log(message, level: .info)
    }
    
    static func warning(_ message: Logging.Logger.Message) {
        log(message, level: .warning)
    }
    
    static func error(_ message: Logging.Logger.Message) {
        log(message, level: .error)
    }
    
    static func fatal(_ message: Logging.Logger.Message) -> Never {
        log(message, level: .critical)
        fatalError(message.description)
    }
    
    private static func log(_ message: Logging.Logger.Message, level: Logging.Logger.Level) {
        logger.log(level: level, message)
    }
}

extension DefaultStringInterpolation {
    mutating func appendInterpolation(pii: String) {
        appendInterpolation("#PII{\(pii)}")
    }
}

fileprivate struct MyLogHandler: LogHandler {
    
    var metadata: Logging.Logger.Metadata = [:]
    
    #if DEBUG
    var logLevel: Logging.Logger.Level = .debug
    #else
    var logLevel: Logging.Logger.Level = .info
    #endif
    
    let osLogger: os.Logger
    let crashlytics: Bool
    nonisolated(unsafe) let piiRegex = #/#PII{(.*)}/#
    
    init(label: String, crashlytics: Bool) {
        osLogger = os.Logger(subsystem: label, category: "app")
        self.crashlytics = crashlytics
    }
    
    subscript(metadataKey metadataKey: String) -> Logging.Logger.Metadata.Value? {
        get {
            return metadata[metadataKey]
        }
        set(newValue) {
            metadata[metadataKey] = newValue
        }
    }
    
    func log(level: Logging.Logger.Level, message: Logging.Logger.Message, metadata: Logging.Logger.Metadata?, source: String, file: String, function: String, line: UInt) {
        let redacted = message.description.replacing(piiRegex) { _ in "(redacted)" }
        let original = message.description.replacing(piiRegex) { $0.output.1 }
        osLogger.log(level: level.osLogLevel, "\(original)")
        if level != .debug && crashlytics {
            Crashlytics.crashlytics().log(redacted)
        }
    }
}

fileprivate extension Logging.Logger.Level {
    var osLogLevel: OSLogType {
        switch self {
        case .trace:
            .debug
        case .debug:
            .debug
        case .info:
            .info
        case .notice:
            .info
        case .warning:
            .error
        case .error:
            .error
        case .critical:
            .fault
        }
    }
}
