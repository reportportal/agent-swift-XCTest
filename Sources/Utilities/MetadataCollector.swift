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
        let osVersion = DeviceHelper.osNameAndVersion()
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
    
    // MARK: - Test Plan Detection
    static func getTestPlanName() -> String? {
        let env = ProcessInfo.processInfo.environment
        if let testPlanName = env["TEST_PLAN_NAME"], !testPlanName.isEmpty {
            return testPlanName
        }
        return nil
    }
    
    // MARK: - Test Plan Metadata
    static func collectTestPlanAttributes(from bundle: Bundle, tags: [String] = []) -> [[String: String]] {
        var attributes: [[String: String]] = []
        
        // Note: Test plan name is now only included in launch name, not as an attribute
        
        // Extract configuration
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
    static func collectAllAttributes(from bundle: Bundle, tags: [String] = []) -> [[String: String]] {
        var allAttributes: [[String: String]] = []
        
        // Add device attributes
        allAttributes.append(contentsOf: collectDeviceAttributes())
        
        // Add test plan attributes
        allAttributes.append(contentsOf: collectTestPlanAttributes(from: bundle, tags: tags))
        
        return allAttributes
    }
}

