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

enum ReportingServiceError: Error {
  case launchIdNotFound
  case testSuiteIdNotFound
}

public class ReportingService {
  
  private let httpClient: HTTPClient
  private let configuration: AgentConfiguration
  private var testBundle: Bundle?
  
  private var launchID: String?
  private var testSuiteStatus = TestStatus.passed
  private var launchStatus = TestStatus.passed
  private var rootSuiteID: String?
  private var testSuiteID: String?
  private var testID = ""
  
  private let timeOutForRequestExpectation = 10.0
  
  init(configuration: AgentConfiguration, testBundle: Bundle? = nil) {
    self.configuration = configuration
    self.testBundle = testBundle
    let baseURL = configuration.reportPortalURL.appendingPathComponent(configuration.projectName)
    httpClient = HTTPClient(baseURL: baseURL)
    httpClient.setPlugins([AuthorizationPlugin(token: configuration.portalToken)])
  }
  
  private func getStoredLaunchID(completion: @escaping (String?) -> Void) throws {
    let endPoint = GetCurrentLaunchEndPoint()
    try httpClient.callEndPoint(endPoint) { (result: LaunchListInfo) in
      guard let launch = result.content.first, launch.status == "IN_PROGRESS" else {
        completion(nil)
        return
      }
      
      completion(launch.uuid)
    }
  }

  func startLaunch() throws {
    let launchSemaphore = DispatchSemaphore(value: 0)
    
    try getStoredLaunchID { (savedLaunchID: String?) in
      guard let savedLaunchID = savedLaunchID else {
        // Collect metadata attributes
        let attributes = self.testBundle != nil 
          ? MetadataCollector.collectAllAttributes(from: self.testBundle!)
          : MetadataCollector.collectDeviceAttributes()
        
        let endPoint = StartLaunchEndPoint(
          launchName: self.configuration.launchName,
          tags: self.configuration.tags,
          mode: self.configuration.launchMode,
          attributes: attributes
        )
        
        do {
          try self.httpClient.callEndPoint(endPoint) { (result: FirstLaunch) in
            self.launchID = result.id
            launchSemaphore.signal()
          }
        } catch let error {
          print("🚨 ReportingService Launch Creation Error: Failed to create new launch on ReportPortal server. Details: \(error.localizedDescription). Check your server configuration and network connectivity.")
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
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      self.rootSuiteID = result.id
      rootSuiteSemaphore.signal()
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
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      self.testSuiteID = result.id
      testSuiteSemaphore.signal()
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
    
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      self.testID = result.id
      testSemaphore.signal()
    }
    
    _ = testSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
  func reportError(message: String) throws {
    guard !testID.isEmpty else {
      print("🚨 ReportingService Error Reporting Failed: Cannot report error '\(message)' - Test ID is missing. This indicates test creation failed. Error will not appear in ReportPortal.")
      return
    }
    
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = PostLogEndPoint(itemID: testID, level: "error", message: message)
    try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
      errorSemaphore.signal()
    }
    
    _ = errorSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
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
    
    print("📸 ReportingService Debug: Attempting to capture screenshot for test ID: \(testID)")
    
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
    
    print("📤 ReportingService Debug: Sending log with \(attachments.count) attachment(s)")
    
    try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
      print("✅ ReportingService Debug: Log API responded with success")
      print("   • Response: \(result)")
      errorSemaphore.signal()
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
    
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      finishTestSemaphore.signal()
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
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      finishTestSuiteSemaphore.signal()
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
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      finishRootSuiteSemaphore.signal()
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
    try httpClient.callEndPoint(endPoint) { (result: LaunchFinish) in
      finishLaunchSemaphore.signal()
    }
    
      _ = finishLaunchSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)
  }
  
}

private extension ReportingService {
  
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
    
    // MARK: - Screenshot Capture
    func captureScreenshot(testCase: XCTestCase?) -> (data: Data, fileExtension: String, mimeType: String)? {
#if canImport(XCTest) && canImport(UIKit)
        // Direct screenshot capture using XCUIScreen
        let screenshot = XCUIScreen.main.screenshot()
        let originalData = screenshot.pngRepresentation
        
        // Convert to UIImage for format processing
        guard let uiImage = UIImage(data: originalData) else {
            return nil
        }
        
        // Smart compression strategy: JPEG works better than PNG for screenshots
        var bestData = originalData
        var isJpeg = false
        
        // Try JPEG compression first (much more effective for screenshots)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
            if jpegData.count < originalData.count {
                bestData = jpegData
                isJpeg = true
            }
        }
        
        // If still too large, try lower quality JPEG
        if bestData.count > 100 * 1024 && !isJpeg { // Still over 100KB and not using JPEG yet
            if let jpegData = uiImage.jpegData(compressionQuality: 0.5) {
                if jpegData.count < bestData.count {
                    bestData = jpegData
                    isJpeg = true
                }
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
    
    // MARK: - Image Utilities
#if canImport(UIKit)
    func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
#endif
    
    // MARK: - Size Utilities
    func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
    
    func createEnhancedErrorMessage(originalMessage: String, testCase: XCTestCase?) -> String {
        // Extract the core error message and clean it up
        var cleanedMessage = originalMessage
        
        // Remove duplicate "Failed to failed to" pattern
        cleanedMessage = cleanedMessage.replacingOccurrences(of: "Failed to failed to", with: "Failed to")
        
        // Extract key information from the message
        let components = extractErrorComponents(from: cleanedMessage)
        
        var enhancedMessage = ""
        
        // Primary error message (simplified)
        enhancedMessage += "TEST FAILURE\n"
        enhancedMessage += "=====================================\n\n"
        
        // Error summary
        if let action = components["action"] {
            enhancedMessage += "Action: \(sanitizeForJSON(action))\n"
        }
        if let element = components["element"] {
            enhancedMessage += "Element: \(sanitizeForJSON(element))\n"
        }
        if let location = components["location"] {
            enhancedMessage += "Location: \(sanitizeForJSON(location))\n"
        }
        if let errorCode = components["errorCode"] {
            enhancedMessage += "Error Code: \(sanitizeForJSON(errorCode))\n"
        }
        
        // Test information
        if let testCase = testCase {
            enhancedMessage += "\nTest Information\n"
            enhancedMessage += "----------------\n"
            let testName = testCase.name.replacingOccurrences(of: "-[", with: "").replacingOccurrences(of: "]", with: "")
            enhancedMessage += "Test: \(sanitizeForJSON(testName))\n"
            
            // Extract file and line from original message
            if let fileMatch = cleanedMessage.range(of: #"(\w+\.swift):\d+"#, options: .regularExpression) {
                let fileInfo = String(cleanedMessage[fileMatch])
                enhancedMessage += "File: \(sanitizeForJSON(fileInfo))\n"
            }
        }
        
        // Device information
#if canImport(UIKit)
        enhancedMessage += "\nDevice Information\n"
        enhancedMessage += "------------------\n"
        enhancedMessage += "Device: \(sanitizeForJSON(UIDevice.current.modelName))\n"
        
        // Handle iPadOS detection
        var osName = UIDevice.current.systemName
        if osName == "iOS" && UIDevice.current.userInterfaceIdiom == .pad {
            let osVersionComponents = UIDevice.current.systemVersion.split(separator: ".")
            if let majorVersion = osVersionComponents.first, let major = Int(majorVersion), major >= 13 {
                osName = "iPadOS"
            }
        }
        enhancedMessage += "OS: \(sanitizeForJSON(osName)) \(sanitizeForJSON(UIDevice.current.systemVersion))\n"
#endif
        
        // Simplified stack trace (only most relevant frames)
        let stackTrace = Thread.callStackSymbols
        if stackTrace.count > 1 {
            enhancedMessage += "\nStack Trace (Top 5)\n"
            enhancedMessage += "-------------------\n"
            let relevantFrames = stackTrace.dropFirst(3).prefix(5)
            for (index, frame) in relevantFrames.enumerated() {
                // Simplify frame display
                if let simplified = simplifyStackFrame(frame) {
                    enhancedMessage += "\(index + 1). \(sanitizeForJSON(simplified))\n"
                }
            }
        }
        
        // Timestamp
        enhancedMessage += "\nTimestamp: \(sanitizeForJSON(TimeHelper.currentTimeAsString()))\n"
        
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
        
        // Extract file location
        if let fileMatch = message.range(of: #"at (\w+\.swift:\d+)"#, options: .regularExpression) {
            let location = String(message[fileMatch]).replacingOccurrences(of: "at ", with: "")
            components["location"] = location
        }
        
        return components
    }
    
    // Helper to simplify stack frame
    private func simplifyStackFrame(_ frame: String) -> String? {
        // Extract the most relevant part of the stack frame
        let components = frame.split(separator: " ").map(String.init)
        
        // Look for the module/function name
        if components.count > 2 {
            var simplified = ""
            
            // Find the module name
            if let moduleIndex = components.firstIndex(where: { !$0.starts(with: "0x") && !CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: $0)) }) {
                simplified = components[moduleIndex]
                
                // Add function name if available
                if moduleIndex + 1 < components.count {
                    let functionPart = components[moduleIndex + 1]
                    if !functionPart.starts(with: "0x") {
                        simplified += " - \(functionPart)"
                    }
                }
            }
            
            return simplified.isEmpty ? nil : simplified
        }
        
        return nil
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

