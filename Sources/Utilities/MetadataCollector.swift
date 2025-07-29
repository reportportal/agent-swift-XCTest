//
//  MetadataCollector.swift
//  RPAgentSwiftXCTest
//
//  Created by Ruslan Popesku
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif
import XCTest

class MetadataCollector {
    
    // MARK: - Device Metadata
    static func collectDeviceAttributes() -> [[String: String]] {
        var attributes: [[String: String]] = []
        
#if canImport(UIKit)
        // Device model
        attributes.append(["key": "device", "value": UIDevice.current.modelName])
        
        // OS version - handle iPadOS separately
        var osName = UIDevice.current.systemName
        if osName == "iOS" && UIDevice.current.userInterfaceIdiom == .pad {
            // iPad running iOS 13+ reports as "iOS" but is actually iPadOS
            let osVersionComponents = UIDevice.current.systemVersion.split(separator: ".")
            if let majorVersion = osVersionComponents.first, let major = Int(majorVersion), major >= 13 {
                osName = "iPadOS"
            }
        }
        let osVersion = "\(osName) \(UIDevice.current.systemVersion)"
        attributes.append(["key": "os", "value": osVersion])
        
        // Simulator detection
        #if targetEnvironment(simulator)
        attributes.append(["key": "simulator", "value": "true"])
        #else
        attributes.append(["key": "simulator", "value": "false"])
        #endif
#else
        // For non-iOS platforms
        attributes.append(["key": "platform", "value": "macOS"])
        if let osVersion = ProcessInfo.processInfo.operatingSystemVersionString.split(separator: " ").last {
            attributes.append(["key": "os", "value": String(osVersion)])
        }
#endif
        
        // App version and build number
        if let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            attributes.append(["key": "version", "value": appVersion])
        }
        
        if let buildNumber = Bundle.main.infoDictionary?["CFBundleVersion"] as? String {
            attributes.append(["key": "build", "value": buildNumber])
        }
        
        return attributes
    }
    
    // MARK: - Test Plan Metadata
    static func collectTestPlanAttributes(from bundle: Bundle) -> [[String: String]] {
        var attributes: [[String: String]] = []
        
        // Try to extract test plan from XCTest environment
        if let testPlanPath = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] {
            let testPlanName = URL(fileURLWithPath: testPlanPath)
                .deletingPathExtension()
                .lastPathComponent
            attributes.append(["key": "testplan", "value": testPlanName])
        }
        
        // Extract configuration from test bundle
        if let testConfiguration = bundle.infoDictionary?["XCTestConfiguration"] as? String {
            attributes.append(["key": "config", "value": testConfiguration])
        } else if ProcessInfo.processInfo.environment["CONFIGURATION"] != nil,
                  let config = ProcessInfo.processInfo.environment["CONFIGURATION"] {
            attributes.append(["key": "config", "value": config])
        } else {
            // Default to Debug if no configuration found
            #if DEBUG
            attributes.append(["key": "config", "value": "Debug"])
            #else
            attributes.append(["key": "config", "value": "Release"])
            #endif
        }
        
        return attributes
    }
    
    // MARK: - Combined Attributes
    static func collectAllAttributes(from bundle: Bundle) -> [[String: String]] {
        var allAttributes: [[String: String]] = []
        
        // Add device attributes
        allAttributes.append(contentsOf: collectDeviceAttributes())
        
        // Add test plan attributes
        allAttributes.append(contentsOf: collectTestPlanAttributes(from: bundle))
        
        return allAttributes
    }
}

