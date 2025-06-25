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
  
  private var launchID: String?
  private var testSuiteStatus = TestStatus.passed
  private var launchStatus = TestStatus.passed
  private var rootSuiteID: String?
  private var testSuiteID: String?
  private var testID = ""
  
  private let timeOutForRequestExpectation = 10.0
  
  init(configuration: AgentConfiguration) {
    self.configuration = configuration
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
        let endPoint = StartLaunchEndPoint(
          launchName: self.configuration.launchName,
          tags: self.configuration.tags,
          mode: self.configuration.launchMode
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
    
    let endPoint = StartItemEndPoint(itemName: suite.name, launchID: launchID, type: .suite)
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
    
    let endPoint = StartItemEndPoint(itemName: suite.name, parentID: rootSuiteID, launchID: launchID, type: .test)
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
    
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    var attachments: [FileAttachment] = []
    
    // Capture screenshot if possible
    if let screenshotData = captureScreenshot(testCase: testCase) {
      // Use safe filename with only digits and underscores to avoid JSON parsing issues
      let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
      let filename = "error_screenshot_\(timestamp).jpg"
      let attachment = FileAttachment(data: screenshotData, filename: filename, mimeType: "image/jpeg")
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
    
    try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
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
    func captureScreenshot(testCase: XCTestCase?) -> Data? {
#if canImport(XCTest) && canImport(UIKit)
        // Direct screenshot capture using XCUIScreen
        let screenshot = XCUIScreen.main.screenshot()
        let originalData = screenshot.pngRepresentation
        
        // Convert to UIImage for PNG compression via resizing
        guard let uiImage = UIImage(data: originalData) else {
            return originalData
        }
        
        // Smart compression strategy: JPEG works better than PNG for screenshots
        var bestData = originalData
        
        // Try JPEG compression first (much more effective for screenshots)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
            if jpegData.count < originalData.count {
                bestData = jpegData
            }
        }
        
        // If still too large, try lower quality
        if bestData.count > 100 * 1024 { // Still over 100KB
            if let jpegData = uiImage.jpegData(compressionQuality: 0.5) {
                if jpegData.count < bestData.count {
                    bestData = jpegData
                }
            }
        }
        
        return bestData
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
        // Sanitize the original message to ensure JSON compatibility
        var enhancedMessage = sanitizeForJSON(originalMessage)
        
        // Add test case information
        if let testCase = testCase {
            enhancedMessage += "\n\n--- Test Case Information ---"
            enhancedMessage += "\nTest: \(sanitizeForJSON(testCase.name))"
            enhancedMessage += "\nClass: \(sanitizeForJSON(String(describing: type(of: testCase))))"
        }
        
        // Add stack trace
        let stackTrace = Thread.callStackSymbols
        if stackTrace.count > 1 {
            enhancedMessage += "\n\n--- Stack Trace ---"
            // Skip the first few frames (this method, reportError, etc.)
            let relevantFrames = stackTrace.dropFirst(3).prefix(10)
            for (index, frame) in relevantFrames.enumerated() {
                enhancedMessage += "\n\(index): \(sanitizeForJSON(frame))"
            }
        }
        
        // Add device information
#if canImport(UIKit)
        enhancedMessage += "\n\n--- Device Information ---"
        enhancedMessage += "\nDevice: \(sanitizeForJSON(UIDevice.current.modelName))"
        enhancedMessage += "\nOS: \(sanitizeForJSON(UIDevice.current.systemName)) \(sanitizeForJSON(UIDevice.current.systemVersion))"
#endif
        
        enhancedMessage += "\n\n--- Timestamp ---"
        enhancedMessage += "\n\(sanitizeForJSON(TimeHelper.currentTimeAsString()))"
        
        return enhancedMessage
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
  
}

extension String {
  var isLowercased: Bool {
    return lowercased() == self
  }
}

