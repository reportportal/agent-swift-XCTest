//
//  RPServices.swift
//
//  Created by Stas Kirichok on 22/08/18.
//  Copyright © 2018 Windmill. All rights reserved.
//

import Foundation
import XCTest
#if canImport(UIKit)
import UIKit
#endif

enum ReportingServiceError: LocalizedError {
  case launchIdNotFound
  case testSuiteIdNotFound
  case configurationError
  case networkError
  case securityViolation
  
  var errorDescription: String? {
    switch self {
    case .launchIdNotFound:
      return "Launch ID not found"
    case .testSuiteIdNotFound:
      return "Test Suite ID not found"
    case .configurationError:
      return "Invalid configuration"
    case .networkError:
      return "Network error occurred"
    case .securityViolation:
      return "Security policy violation"
    }
  }
}

public final class ReportingService {
  
  // MARK: - Properties
  
  private let httpClient: HTTPClient
  private let configuration: AgentConfiguration
  private var testBundle: Bundle?
  
  private(set) var launchID: String?
  private var testSuiteStatus = TestStatus.passed
  private var launchStatus = TestStatus.passed
  private(set) var rootSuiteID: String?
  private(set) var testSuiteID: String?
  private var testID = ""
  
  private let timeOutForRequestExpectation: TimeInterval = 10.0
  
  // MARK: - Initialization
  
  init(configuration: AgentConfiguration, testBundle: Bundle? = nil) {
    self.configuration = configuration
    self.testBundle = testBundle
    let baseURL = configuration.reportPortalURL.appendingPathComponent(configuration.projectName)
    httpClient = HTTPClient(baseURL: baseURL)
    httpClient.setPlugins([AuthorizationPlugin(token: configuration.portalToken)])
  }
  
  func startLaunch() throws {
    let launchSemaphore = DispatchSemaphore(value: 0)
    
    try getStoredLaunchID { (savedLaunchID: String?) in
      guard let savedLaunchID = savedLaunchID else {
        // Collect metadata attributes
        let attributes: [[String: String]]
        if let bundle = self.testBundle {
          attributes = MetadataCollector.collectAllAttributes(from: bundle, tags: self.configuration.tags)
        } else {
          attributes = MetadataCollector.collectDeviceAttributes()
        }
        
        // Get test plan name for launch name enhancement
        let testPlanName = MetadataCollector.getTestPlanName()
        let enhancedLaunchName = self.buildEnhancedLaunchName(
          baseLaunchName: self.configuration.launchName,
          testPlanName: testPlanName
        )
        
        let endPoint = StartLaunchEndPoint(
          launchName: enhancedLaunchName,
          tags: self.configuration.tags,
          mode: self.configuration.launchMode,
          attributes: attributes
        )
        
        do {
          try self.httpClient.callEndPoint(endPoint) { (result: FirstLaunch) in
            self.launchID = result.id
            print("✅ ReportPortal Launch created successfully with ID: \(result.id)")
            launchSemaphore.signal()
          }
        } catch let error {
          print("🚨 ReportingService Launch Creation Error: Failed to create new launch on ReportPortal server. Details: \(error.localizedDescription). Check your server configuration and network connectivity.")
          launchSemaphore.signal() // Signal even on error to prevent deadlock
        }
        
        return
      }
      
      self.launchID = savedLaunchID
      launchSemaphore.signal()
    }
    
    _ = launchSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func startRootSuite(_ suite: XCTestSuite) throws {
    guard let launchID = launchID else {
      print("🚨 ReportingService Critical Error: Cannot start root suite '\(suite.name)' - Launch ID is missing. This indicates launch creation failed completely. All test results will be lost.")
      throw ReportingServiceError.launchIdNotFound
    }
    
    let rootSuiteSemaphore = DispatchSemaphore(value: 0)
    
    // Apply dynamic suite naming with tags
    let suiteName = generateDynamicSuiteName(baseName: suite.name)
    
    let endPoint = StartItemEndPoint(itemName: suiteName, launchID: launchID, type: .suite)
    do {
      try httpClient.callEndPoint(endPoint) { (result: Item) in
        self.rootSuiteID = result.id
        rootSuiteSemaphore.signal()
      }
    } catch {
      print("🚨 ReportingService: Failed to start root suite '\(suite.name)': \(error.localizedDescription)")
      rootSuiteSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = rootSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func startTestSuite(_ suite: XCTestSuite) throws {
    guard let launchID = launchID else {
      print("🚨 ReportingService Critical Error: Cannot start test suite '\(suite.name)' - Launch ID is missing.")
      throw ReportingServiceError.launchIdNotFound
    }
    guard let rootSuiteID = rootSuiteID else {
      print("🚨 ReportingService Critical Error: Cannot start test suite '\(suite.name)' - Root Suite ID is missing.")
      throw ReportingServiceError.launchIdNotFound
    }
    
    let testSuiteSemaphore = DispatchSemaphore(value: 0)
    
    // Apply dynamic suite naming with tags
    let suiteName = generateDynamicSuiteName(baseName: suite.name)
    
    let endPoint = StartItemEndPoint(itemName: suiteName, parentID: rootSuiteID, launchID: launchID, type: .test)
    do {
      try httpClient.callEndPoint(endPoint) { (result: Item) in
        self.testSuiteID = result.id
        testSuiteSemaphore.signal()
      }
    } catch {
      print("🚨 ReportingService: Failed to start test suite '\(suite.name)': \(error.localizedDescription)")
      testSuiteSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = testSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func startTest(_ test: XCTestCase) throws {
    guard let launchID = launchID else {
      print("🚨 ReportingService Critical Error: Cannot start test '\(test.name)' - Launch ID is missing.")
      throw ReportingServiceError.launchIdNotFound
    }
    guard let testSuiteID = testSuiteID else {
      print("🚨 ReportingService Critical Error: Cannot start test '\(test.name)' - Test Suite ID is missing.")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    let testSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = StartItemEndPoint(
      itemName: extractTestName(from: test),
      parentID: testSuiteID,
      launchID: launchID,
      type: .step
    )
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: Item) in
        self.testID = result.id
        testSemaphore.signal()
      }
    } catch {
      print("🚨 ReportingService: Failed to start test '\(test.name)': \(error.localizedDescription)")
      testSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = testSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
    
  func startTest(_ test: XCTestCase, featureName: String?, scenarioName: String?) throws {
    guard let launchID = launchID else {
      print("🚨 ReportingService Critical Error: Cannot start test '\(test.name)' - Launch ID is missing.")
      throw ReportingServiceError.launchIdNotFound
    }
    guard let testSuiteID = testSuiteID else {
      print("🚨 ReportingService Critical Error: Cannot start test '\(test.name)' - Test Suite ID is missing.")
      throw ReportingServiceError.testSuiteIdNotFound
    }
        
    let testSemaphore = DispatchSemaphore(value: 0)
        
    // Build a more descriptive name for Gherkin scenarios
    var finalName: String
    if let feature = featureName, let scenario = scenarioName {
      finalName = "\(feature) - \(scenario)"
    } else {
      finalName = extractTestName(from: test)
    }
        
    let endPoint = StartItemEndPoint(
      itemName: finalName,
      parentID: testSuiteID,
      launchID: launchID,
      type: .step
    )
        
    do {
      try httpClient.callEndPoint(endPoint) { (result: Item) in
          self.testID = result.id
          testSemaphore.signal()
      }
    } catch {
      print("🚨 ReportingService: Failed to start test '\(finalName)': \(error.localizedDescription)")
      testSemaphore.signal()
      throw error
    }
        
    _ = testSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  // Enhanced error reporting with screenshot support
  func reportErrorWithScreenshot(message: String, testCase: XCTestCase? = nil) throws {
    guard let launchID = launchID else {
      print("🚨 ReportingService Screenshot Error: Cannot report error with screenshot - Launch ID is missing. Error: '\(message)'")
      throw ReportingServiceError.launchIdNotFound
    }
    
    guard !testID.isEmpty else {
      print("🚨 ReportingService Screenshot Error: Cannot report error with screenshot - Test ID is missing. Error: '\(message)'")
      return
    }
    
    
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    var attachments: [FileAttachment] = []
    
    // Capture screenshot with proper format handling
    if let screenshotResult = captureScreenshot(testCase: testCase) {
      // Use safe filename with only digits and underscores to avoid JSON parsing issues
      let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
      let filename = "error_screenshot_\(timestamp).\(screenshotResult.fileExtension)"
      let attachment = FileAttachment(data: screenshotResult.data, filename: filename, mimeType: screenshotResult.mimeType)
      attachments.append(attachment)
    } else {
      print("⚠️ ReportingService Screenshot Warning: Failed to capture screenshot for error: '\(message)'")
    }
    
    // Enhanced error message with stack trace
    let enhancedMessage = createEnhancedErrorMessage(originalMessage: message, testCase: testCase)
    
    let endPoint = PostLogEndPoint(
      itemUuid: testID,
      launchUuid: launchID,
      level: "error",
      message: enhancedMessage,
      attachments: attachments
    )
    
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
        errorSemaphore.signal()
      }
    } catch {
      print("🚨 ReportingService: Failed to report error with screenshot: \(error.localizedDescription)")
      errorSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = errorSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
    
  
  func finishTest(_ test: XCTestCase) throws {
    let testStatus = test.testRun!.hasSucceeded ? TestStatus.passed : TestStatus.failed
    if testStatus == .failed {
      testSuiteStatus = .failed
      launchStatus = .failed
    }
    
    let finishTestSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: testID, status: testStatus, launchID: self.launchID ?? "")
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: Finish) in
        finishTestSemaphore.signal()
      }
    } catch {
      print("⚠️ ReportingService: Failed to finish test '\(test.name)': \(error.localizedDescription)")
      finishTestSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = finishTestSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func finishTestSuite() throws {
    guard let testSuiteID = testSuiteID else {
      print("🚨 ReportingService Critical Error: Cannot finish test suite - Test Suite ID is missing.")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    let finishTestSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: testSuiteID, status: testSuiteStatus, launchID: self.launchID ?? "")
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: Finish) in
        finishTestSuiteSemaphore.signal()
      }
    } catch {
      print("⚠️ ReportingService: Failed to finish test suite: \(error.localizedDescription)")
      finishTestSuiteSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = finishTestSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func finishRootSuite() throws {
    guard let rootSuiteID = rootSuiteID else {
      print("🚨 ReportingService Critical Error: Cannot finish root suite - Root Suite ID is missing.")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    let finishRootSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: rootSuiteID, status: launchStatus, launchID: self.launchID ?? "")
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: Finish) in
        finishRootSuiteSemaphore.signal()
      }
    } catch {
      print("⚠️ ReportingService: Failed to finish root suite: \(error.localizedDescription)")
      finishRootSuiteSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = finishRootSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func finishLaunch() throws {
    guard configuration.shouldFinishLaunch else {
      print("🎬✅ ReportingService: Skip finish till next test bundle")
      return
    }
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when finishing launch")
      throw ReportingServiceError.launchIdNotFound
    }
    
    let finishLaunchSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = FinishLaunchEndPoint(launchID: launchID, status: launchStatus)
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: LaunchFinish) in
        finishLaunchSemaphore.signal()
      }
    } catch {
      print("⚠️ ReportingService: Failed to finish launch: \(error.localizedDescription)")
      finishLaunchSemaphore.signal() // Signal to prevent deadlock
      throw error
    }
    
    _ = finishLaunchSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
}

private extension ReportingService {
  
  func getStoredLaunchID(completion: @escaping (String?) -> Void) throws {
    let endPoint = GetCurrentLaunchEndPoint()
    try httpClient.callEndPoint(endPoint) { (result: LaunchListInfo) in
      guard let launch = result.content.first, launch.status == "IN_PROGRESS" else {
        completion(nil)
        return
      }
      
      completion(launch.uuid)
    }
  }
  
  func extractTestName(from test: XCTestCase) -> String {
    let originName = test.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let components = originName.components(separatedBy: " ")
    var result = components[1].replacingOccurrences(of: "]", with: "")
    
    if configuration.testNameRules.contains(.stripTestPrefix) {
      result.removeFirst(4)
    }
    if configuration.testNameRules.contains(.whiteSpaceOnUnderscore) {
      result = result.replacingOccurrences(of: "_", with: " ")
    }
    if configuration.testNameRules.contains(.whiteSpaceOnCamelCase) {
      var insertOffset = 0
      for index in 1..<result.count {
        let currentIndex = result.index(result.startIndex, offsetBy: index + insertOffset)
        let previousIndex = result.index(result.startIndex, offsetBy: index - 1 + insertOffset)
        if String(result[previousIndex]).isLowercased && !String(result[currentIndex]).isLowercased {
          result.insert(" ", at: currentIndex)
          insertOffset += 1
        }
      }
    }
    
    return result
  }
    
  func captureScreenshot(testCase: XCTestCase?) -> (data: Data, fileExtension: String, mimeType: String)? {
#if canImport(XCTest) && canImport(UIKit)
    // Direct screenshot capture using XCUIScreen
    // Guard: ensure UI testing context (XCUIScreen is available at runtime)
    guard NSClassFromString("XCUIScreen") != nil else { return nil }
    let screenshot = XCUIScreen.main.screenshot()
    let originalData = screenshot.pngRepresentation

    // Convert to UIImage for format processing
    guard let uiImage = UIImage(data: originalData) else {
      return nil
    }

    // Smart compression: prefer JPEG and target max size (~2MB)
    let maxBytes = 2_000_000
    var bestData = originalData
    var isJpeg = false
        
    // Iteratively compress to approach size cap
    var qualities: [CGFloat] = [0.7, 0.6, 0.5, 0.4, 0.3]
    for q in qualities {
      if let jpeg = uiImage.jpegData(compressionQuality: q) {
        if jpeg.count < bestData.count || bestData.count > maxBytes {
          bestData = jpeg
          isJpeg = true
        }
        if bestData.count <= maxBytes { break }
      }
    }
        
    // Return appropriate format information based on what we're actually sending
    if isJpeg {
        return (bestData, "jpg", "image/jpeg")
    } else {
        return (bestData, "png", "image/png")
    }
#else
    print("🚨 ReportingService Platform Error: Screenshot capture not available on this platform. Only iOS supports screenshot capture.")
    return nil
#endif
  }
    
    func createEnhancedErrorMessage(originalMessage: String, testCase: XCTestCase?) -> String {
        // Start with the original message as-is (it already has the native format)
        // This preserves "Test failed on line X in file.swift: description" format
        var enhancedMessage = originalMessage
        
        // Clean up only obvious duplicates without breaking the native format
        enhancedMessage = enhancedMessage.replacingOccurrences(of: "Failed to failed to", with: "Failed to")
        
        // Add a separator before additional details
        enhancedMessage += "\n\n=====================================\n"
        enhancedMessage += "Additional Details:\n"
        enhancedMessage += "=====================================\n"
        
        // Extract key information from the message for structured details
        let components = extractErrorComponents(from: originalMessage)
        
        // Add structured error components if found
        var hasComponents = false
        if let action = components["action"] {
            enhancedMessage += "Action: \(sanitizeForJSON(action))\n"
            hasComponents = true
        }
        if let element = components["element"] {
            enhancedMessage += "Element: \(sanitizeForJSON(element))\n"
            hasComponents = true
        }
        if let errorCode = components["errorCode"] {
            enhancedMessage += "Error Code: \(sanitizeForJSON(errorCode))\n"
            hasComponents = true
        }
        
        if !hasComponents {
            // If no specific components found, don't add empty section
            enhancedMessage = originalMessage + "\n"
        }
        
        // Test information
        if let testCase = testCase {
            enhancedMessage += "\nTest Context:\n"
            enhancedMessage += "-------------\n"
            let testName = testCase.name.replacingOccurrences(of: "-[", with: "").replacingOccurrences(of: "]", with: "")
            enhancedMessage += "Test Name: \(sanitizeForJSON(testName))\n"
            
            // Add test execution time
            if let testRun = testCase.testRun {
                enhancedMessage += "Execution Time: \(String(format: "%.3f", testRun.totalDuration)) seconds\n"
            }
        }
        
        // Tags information - single line
        if !configuration.tags.isEmpty {
            enhancedMessage += "\nTags: \(configuration.tags.joined(separator: ", "))\n"
        }
        
        // Environment information
        enhancedMessage += "\nEnvironment:\n"
        enhancedMessage += "------------\n"
        
        // Test Plan information
        if let testPlanName = MetadataCollector.getTestPlanName() {
            enhancedMessage += "Test Plan: \(sanitizeForJSON(testPlanName))\n"
        }
        
        // Configuration (Debug/Release)
        #if DEBUG
        enhancedMessage += "Build Configuration: Debug\n"
        #else
        enhancedMessage += "Build Configuration: Release\n"
        #endif
        
        // Device information
#if canImport(UIKit)
        enhancedMessage += "\nDevice Information:\n"
        enhancedMessage += "------------------\n"
        enhancedMessage += "Device: \(sanitizeForJSON(UIDevice.current.modelName))\n"
        enhancedMessage += "OS: \(sanitizeForJSON(DeviceHelper.osNameAndVersion()))\n"
        
        // Simulator vs Device
        #if targetEnvironment(simulator)
        enhancedMessage += "Platform: Simulator\n"
        #else
        enhancedMessage += "Platform: Physical Device\n"
        #endif
        
        // Memory info (if available)
        let deviceInfo = ProcessInfo.processInfo
        let memoryGB = Double(deviceInfo.physicalMemory) / (1024 * 1024 * 1024)
        enhancedMessage += "Memory: \(String(format: "%.1f", memoryGB)) GB\n"
#endif
        
        // Process information
        enhancedMessage += "\nProcess Information:\n"
        enhancedMessage += "-------------------\n"
        let processInfo = ProcessInfo.processInfo
        enhancedMessage += "Process ID: \(processInfo.processIdentifier)\n"
        enhancedMessage += "Process Name: \(sanitizeForJSON(processInfo.processName))\n"
        
        // Bundle information
        if let bundle = Bundle.main.infoDictionary {
            if let appVersion = bundle["CFBundleShortVersionString"] as? String {
                enhancedMessage += "App Version: \(sanitizeForJSON(appVersion))\n"
            }
            if let buildNumber = bundle["CFBundleVersion"] as? String {
                enhancedMessage += "Build Number: \(sanitizeForJSON(buildNumber))\n"
            }
            if let bundleId = bundle["CFBundleIdentifier"] as? String {
                enhancedMessage += "Bundle ID: \(sanitizeForJSON(bundleId))\n"
            }
        }
        
        // Human-readable timestamp
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.locale = Locale.current
        let humanReadableTime = formatter.string(from: Date())
        enhancedMessage += "\nTimestamp: \(humanReadableTime)\n"
        
        
        return enhancedMessage
    }
    
    // Helper to extract error components
    private func extractErrorComponents(from message: String) -> [String: String] {
        var components: [String: String] = [:]
        
        // Extract action (e.g., "scroll to visible")
        if let actionMatch = message.range(of: #"Failed to (.+?) (?:Key|element)"#, options: .regularExpression) {
            let action = String(message[actionMatch]).replacingOccurrences(of: "Failed to ", with: "").replacingOccurrences(of: " Key", with: "").replacingOccurrences(of: " element", with: "")
            components["action"] = action
        }
        
        // Extract element info (e.g., "label: '9'")
        if let labelMatch = message.range(of: #"label: '[^']+'"#, options: .regularExpression) {
            components["element"] = String(message[labelMatch])
        }
        
        // Extract error code (e.g., "kAXErrorCannotComplete")
        if let errorMatch = message.range(of: #"Error \w+"#, options: .regularExpression) {
            components["errorCode"] = String(message[errorMatch])
        }
        
        return components
    }
    
    // Structure to hold enhanced stack frame information
    private struct StackFrameInfo {
        let description: String
        let module: String
        let function: String
        let lineNumber: Int
    }
   
    // MARK: - JSON Safety Helper
    func sanitizeForJSON(_ input: String) -> String {
        // Handle the most common problematic characters that can break JSON
        var sanitized = input
        
        // Replace control characters (except \t, \n, \r) with spaces
        sanitized = sanitized.replacingOccurrences(of: "\u{0000}", with: "") // NULL
        sanitized = sanitized.replacingOccurrences(of: "\u{0001}", with: " ") // SOH
        sanitized = sanitized.replacingOccurrences(of: "\u{0002}", with: " ") // STX
        sanitized = sanitized.replacingOccurrences(of: "\u{0003}", with: " ") // ETX
        sanitized = sanitized.replacingOccurrences(of: "\u{0004}", with: " ") // EOT
        sanitized = sanitized.replacingOccurrences(of: "\u{0005}", with: " ") // ENQ
        sanitized = sanitized.replacingOccurrences(of: "\u{0006}", with: " ") // ACK
        sanitized = sanitized.replacingOccurrences(of: "\u{0007}", with: " ") // BEL
        sanitized = sanitized.replacingOccurrences(of: "\u{0008}", with: " ") // BS
        // Keep \t (0009)
        // Keep \n (000A)
        sanitized = sanitized.replacingOccurrences(of: "\u{000B}", with: " ") // VT
        sanitized = sanitized.replacingOccurrences(of: "\u{000C}", with: " ") // FF
        // Keep \r (000D)
        sanitized = sanitized.replacingOccurrences(of: "\u{000E}", with: " ") // SO
        sanitized = sanitized.replacingOccurrences(of: "\u{000F}", with: " ") // SI
        
        // Continue for other control characters 0010-001F
        for unicode in 0x10...0x1F {
            let char = Character(UnicodeScalar(unicode)!)
            sanitized = sanitized.replacingOccurrences(of: String(char), with: " ")
        }
        
        // Handle DEL character
        sanitized = sanitized.replacingOccurrences(of: "\u{007F}", with: " ")
        
        // Note: We don't escape quotes or backslashes here because JSONSerialization.data should handle that
        // But we could add additional checks if needed
        
        return sanitized
    }
    
    // MARK: - Enhanced Launch Naming
    func buildEnhancedLaunchName(baseLaunchName: String, testPlanName: String?) -> String {
        if let testPlan = testPlanName, !testPlan.isEmpty {
            // Replace spaces with underscores for better display in ReportPortal
            let sanitizedTestPlan = testPlan.replacingOccurrences(of: " ", with: "_")
            return "\(baseLaunchName): \(sanitizedTestPlan)"
        }
        return baseLaunchName
    }
    
    // MARK: - Dynamic Suite Naming
    func generateDynamicSuiteName(baseName: String) -> String {
        // If no tags configured, return original name
        guard !configuration.tags.isEmpty else {
            return baseName
        }
        
        // Clean the base name - remove .xctest extension if present
        var cleanedBaseName = baseName
        if cleanedBaseName.hasSuffix(".xctest") {
            cleanedBaseName = String(cleanedBaseName.dropLast(7))
        }
        
        // Join tags with underscores and append to suite name
        let tagsString = configuration.tags.joined(separator: "_")
        return "\(cleanedBaseName)_\(tagsString)"
    }
  
}

extension String {
  var isLowercased: Bool {
    return lowercased() == self
  }
}

extension ReportingService {
    public func log(message: String, level: LogLevel, attachment: (data: Data, fileExtension: String, mimeType: String)? = nil) throws {
        guard let launchID = launchID, !testID.isEmpty else {
            print("⚠️ ReportingService: Cannot log message '\(message)' - missing launchID/testID.")
            return
        }
        
        var attachments: [FileAttachment] = []
        if let att = attachment {
            let filename = "step_screenshot_\(Int(Date().timeIntervalSince1970)).\(att.fileExtension)"
            attachments.append(FileAttachment(data: att.data, filename: filename, mimeType: att.mimeType))
        }
        
        let endPoint = PostLogEndPoint(
            itemUuid: testID,
            launchUuid: launchID,
            level: level.rawValue,
            message: message,
            attachments: attachments
        )
        
        try httpClient.callEndPoint(endPoint) { (_: LogResponse) in }
    }
}

public enum LogLevel: String {
    case info
    case warn
    case error
    case debug
}

