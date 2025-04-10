//
//  MacNativeBundle.swift
//  waifu2x
//
//  Created by Yi Xie on 2022/2/24.
//  Copyright © 2022 xieyi. All rights reserved.
//
//  Don't use --deep to code sign: https://developer.apple.com/forums/thread/129980
//  More info about trusted execution: https://developer.apple.com/forums/thread/706442

import Foundation

class MacNativeBundle {
    private static func loadClass<T: NSObjectProtocol>(_ className: String) throws -> T {
        /// 1. Form the plugin's bundle URL
        let bundleFileName = "MacNativeHelper.bundle"
        guard let bundleURL = Bundle.main.privateFrameworksURL?.appendingPathComponent(bundleFileName) else {
            throw MacNativeBundleError.pluginDirNotFound
        }
        /// 2. Create a bundle instance with the plugin URL
        guard let bundle = Bundle(url: bundleURL) else {
            throw MacNativeBundleError.bundleNotFound
        }
        /// 3. Load the bundle and our plugin class
        guard let pluginClass = bundle.classNamed(className) as? NSObject.Type else {
            throw MacNativeBundleError.classNotFound(className)
        }
        /// 4. Create an instance of the plugin class
        guard let pluginObject = pluginClass.init() as? T else {
            throw MacNativeBundleError.cannotInitObject(className)
        }
        return pluginObject
    }
    
    static func loadUIHelper() throws -> UIHelper {
        return try loadClass("MacNativeHelper.UIHelperImpl")
    }
}

enum MacNativeBundleError: Error, LocalizedError {
    var errorDescription: String? {
        switch self {
        case .pluginDirNotFound:
            return "Cannot load plugins dir"
        case .bundleNotFound:
            return "Cannot find native plugin bundle"
        case .classNotFound(let string):
            return "Cannot find class " + string
        case .cannotInitObject(let string):
            return "Cannot init object from class " + string
        }
    }
    case pluginDirNotFound
    case bundleNotFound
    case classNotFound(String)
    case cannotInitObject(String)
}
