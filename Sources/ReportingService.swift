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
    print("🚀 ReportingService: Initializing with configuration")
    self.configuration = configuration
    let baseURL = configuration.reportPortalURL.appendingPathComponent(configuration.projectName)
    httpClient = HTTPClient(baseURL: baseURL)
    httpClient.setPlugins([AuthorizationPlugin(token: configuration.portalToken)])
    print("🚀 ReportingService: Initialization complete")
  }
  
  private func getStoredLaunchID(completion: @escaping (String?) -> Void) throws {
    print("🔍 ReportingService: Getting stored launch ID")
    let endPoint = GetCurrentLaunchEndPoint()
    try httpClient.callEndPoint(endPoint) { (result: LaunchListInfo) in
      print("🔍 ReportingService: Received launch list response")
      guard let launch = result.content.first, launch.status == "IN_PROGRESS" else {
        print("🔍 ReportingService: No in-progress launch found")
        completion(nil)
        return
      }
      
      completion(launch.uuid)
    }
  }

  func startLaunch() throws {
    print("🎬 ReportingService: Starting launch...")
    
    // Create INDIVIDUAL semaphore for this operation only
    let launchSemaphore = DispatchSemaphore(value: 0)
    
    try getStoredLaunchID { (savedLaunchID: String?) in
      guard let savedLaunchID = savedLaunchID else {
        print("🎬 ReportingService: No saved launch found, creating new launch")
        let endPoint = StartLaunchEndPoint(
          launchName: self.configuration.launchName,
          tags: self.configuration.tags,
          mode: self.configuration.launchMode
        )
        
        do {
          try self.httpClient.callEndPoint(endPoint) { (result: FirstLaunch) in
            print("🎬 ReportingService: New launch created with ID: \(result.id)")
            self.launchID = result.id
            print("🎬 ReportingService: Signaling semaphore after launch creation")
            launchSemaphore.signal()  // Signal THIS operation's semaphore
          }
        } catch let error {
          print("❌ ReportingService: Error creating launch: \(error)")
        }
        
        return
      }
      
      print("🎬 ReportingService: Using existing launch ID: \(savedLaunchID)")
      self.launchID = savedLaunchID
      print("🎬 ReportingService: Signaling semaphore after using existing launch")
      launchSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("🎬 ReportingService: Waiting for semaphore...")
    let result = launchSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("🎬 ReportingService: Semaphore wait result: \(result), launchID: \(launchID ?? "nil")")
  }
  
  func startRootSuite(_ suite: XCTestSuite) throws {
    print("📁 ReportingService: Starting root suite: \(suite.name)")
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when starting root suite")
      throw ReportingServiceError.launchIdNotFound
    }
    
    print("📁 ReportingService: LaunchID available: \(launchID)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let rootSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = StartItemEndPoint(itemName: suite.name, launchID: launchID, type: .suite)
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      print("📁 ReportingService: Root suite created with ID: \(result.id)")
      self.rootSuiteID = result.id
      print("📁 ReportingService: Signaling semaphore after root suite creation")
      rootSuiteSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("📁 ReportingService: Waiting for root suite semaphore...")
    let result = rootSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("📁 ReportingService: Root suite semaphore wait result: \(result), rootSuiteID: \(rootSuiteID ?? "nil")")
  }
  
  func startTestSuite(_ suite: XCTestSuite) throws {
    print("📂 ReportingService: Starting test suite: \(suite.name)")
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when starting test suite")
      throw ReportingServiceError.launchIdNotFound
    }
    guard let rootSuiteID = rootSuiteID else {
      print("❌ ReportingService: RootSuiteID not found when starting test suite")
      throw ReportingServiceError.launchIdNotFound
    }
    
    print("📂 ReportingService: LaunchID: \(launchID), RootSuiteID: \(rootSuiteID)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let testSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = StartItemEndPoint(itemName: suite.name, parentID: rootSuiteID, launchID: launchID, type: .test)
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      print("📂 ReportingService: Test suite created with ID: \(result.id)")
      self.testSuiteID = result.id
      print("📂 ReportingService: Signaling semaphore after test suite creation")
      testSuiteSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("📂 ReportingService: Waiting for test suite semaphore...")
    let result = testSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("📂 ReportingService: Test suite semaphore wait result: \(result), testSuiteID: \(testSuiteID ?? "nil")")
  }
  
  func startTest(_ test: XCTestCase) throws {
    print("🧪 ReportingService: Starting test: \(test.name)")
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when starting test")
      throw ReportingServiceError.launchIdNotFound
    }
    guard let testSuiteID = testSuiteID else {
      print("❌ ReportingService: TestSuiteID not found when starting test")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    print("🧪 ReportingService: LaunchID: \(launchID), TestSuiteID: \(testSuiteID)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let testSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = StartItemEndPoint(
      itemName: extractTestName(from: test),
      parentID: testSuiteID,
      launchID: launchID,
      type: .step
    )
    
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      print("🧪 ReportingService: Test created with ID: \(result.id)")
      self.testID = result.id
      print("🧪 ReportingService: Signaling semaphore after test creation")
      testSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("🧪 ReportingService: Waiting for test semaphore...")
    let result = testSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("🧪 ReportingService: Test semaphore wait result: \(result), testID: \(testID)")
  }
  
  func reportError(message: String) throws {
    print("🚨 ReportingService: Reporting error: \(message)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = PostLogEndPoint(itemID: testID, level: "error", message: message)
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      print("🚨 ReportingService: Error reported, signaling semaphore")
      errorSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("🚨 ReportingService: Waiting for error report semaphore...")
    let result = errorSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("🚨 ReportingService: Error report semaphore wait result: \(result)")
  }
  
  // Enhanced error reporting with screenshot support
  func reportErrorWithScreenshot(message: String, testCase: XCTestCase? = nil) throws {
    print("🚨📸 ReportingService: Reporting error with screenshot: \(message)")
    
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when reporting error")
      throw ReportingServiceError.launchIdNotFound
    }
    
    // Create INDIVIDUAL semaphore for this operation only
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    var attachments: [FileAttachment] = []
    
    // Capture screenshot if possible (enabled for Proxyman debugging)
    if let screenshotData = captureScreenshot(testCase: testCase) {
      // Use safe filename with only digits and underscores to avoid JSON parsing issues
      let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
      let filename = "error_screenshot_\(timestamp).jpg"
      let attachment = FileAttachment(data: screenshotData, filename: filename, mimeType: "image/jpeg")
      attachments.append(attachment)
      print("🚨📸 ReportingService: Screenshot captured, size: \(screenshotData.count) bytes")
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
    
    try httpClient.callEndPoint(endPoint) { (result: Item) in
      print("🚨📸 ReportingService: Error with screenshot reported, signaling semaphore")
      errorSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("🚨📸 ReportingService: Waiting for error report semaphore...")
    let result = errorSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("🚨📸 ReportingService: Error report semaphore wait result: \(result)")
  }
    
    // MARK: - Screenshot Capture
    private func captureScreenshot(testCase: XCTestCase?) -> Data? {
#if canImport(XCTest) && canImport(UIKit)
        // Direct screenshot capture using XCUIScreen
        let screenshot = XCUIScreen.main.screenshot()
        let originalData = screenshot.pngRepresentation
        
        // Convert to UIImage for PNG compression via resizing
        guard let uiImage = UIImage(data: originalData) else {
            print("🚨📸 ReportingService: Failed to convert screenshot to UIImage, using original PNG")
            return originalData
        }
        
        // Smart compression strategy: JPEG works better than PNG for screenshots
        var bestData = originalData
        var bestFormat = "PNG (original)"
        
        // Try JPEG compression first (much more effective for screenshots)
        if let jpegData = uiImage.jpegData(compressionQuality: 0.7) {
            if jpegData.count < originalData.count {
                bestData = jpegData
                bestFormat = "JPEG (70%)"
                print("🚨📸 ReportingService: JPEG compression successful")
            }
        }
        
        // If still too large, try lower quality
        if bestData.count > 100 * 1024 { // Still over 100KB
            if let jpegData = uiImage.jpegData(compressionQuality: 0.5) {
                if jpegData.count < bestData.count {
                    bestData = jpegData
                    bestFormat = "JPEG (50%)"
                    print("🚨📸 ReportingService: Higher JPEG compression applied")
                }
            }
        }
        
        // Detailed PNG compression analysis
        let originalSizeFormatted = formatBytes(originalData.count)
        let finalSizeFormatted = formatBytes(bestData.count)
        let compressionRatio = Double(bestData.count) / Double(originalData.count)
        let sizeSavings = originalData.count - bestData.count
        let sizeSavingsFormatted = formatBytes(abs(sizeSavings))
        
        print("🚨📸 ReportingService: PNG compression analysis:")
        print("  📏 Original PNG: \(originalData.count) bytes (\(originalSizeFormatted))")
        print("  📏 Compressed \(bestFormat): \(bestData.count) bytes (\(finalSizeFormatted))")
        print("  📊 Final size ratio: \(String(format: "%.1f", compressionRatio * 100))% of original")
        
        if sizeSavings > 0 {
            print("  💾 Size reduction: \(sizeSavings) bytes (\(sizeSavingsFormatted))")
            print("  🎯 Compression efficiency: \(String(format: "%.1f", (1 - compressionRatio) * 100))% smaller")
        } else {
            print("  📈 No size reduction achieved, using original PNG")
        }
        
        print("  ✅ Final format: \(bestFormat), size: \(formatBytes(bestData.count))")
        
        // Check against your preferred 100KB threshold
        let preferredMaxSize = 100 * 1024 // 100KB
        if bestData.count > preferredMaxSize {
            let overageFormatted = formatBytes(bestData.count - preferredMaxSize)
            print("  ⚠️  Warning: Screenshot exceeds 100KB by \(overageFormatted)")
        } else {
            print("  ✅ Screenshot is within 100KB limit")
        }
        
        return bestData
#else
        print("🚨📸 ReportingService: Screenshot capture not available on this platform")
        return nil
#endif
    }
    
    // MARK: - Image Utilities
    #if canImport(UIKit)
    private func resizeImage(_ image: UIImage, to newSize: CGSize) -> UIImage? {
        UIGraphicsBeginImageContextWithOptions(newSize, false, 0.0)
        image.draw(in: CGRect(origin: .zero, size: newSize))
        let resizedImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()
        return resizedImage
    }
    #endif
    
    // MARK: - Size Utilities
    private func formatBytes(_ bytes: Int) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
  
  private func createEnhancedErrorMessage(originalMessage: String, testCase: XCTestCase?) -> String {
    // TEMPORARY: Use simple static message to test if complex messages are the issue
    return "Test error"
    
    // TODO: Restore full enhanced message once we confirm this fixes the issue
    /*
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
    */
  }
  
  // MARK: - JSON Safety Helper
  private func sanitizeForJSON(_ input: String) -> String {
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
    
    print("🔍 ReportingService: Message sanitization - original length: \(input.count), sanitized length: \(sanitized.count)")
    
    return sanitized
  }
  
  func finishTest(_ test: XCTestCase) throws {
    print("✅ ReportingService: Finishing test: \(test.name)")
    let testStatus = test.testRun!.hasSucceeded ? TestStatus.passed : TestStatus.failed
    print("✅ ReportingService: Test status: \(testStatus)")
    if testStatus == .failed {
      testSuiteStatus = .failed
      launchStatus = .failed
    }
    
    // Create INDIVIDUAL semaphore for this operation only
    let finishTestSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: testID, status: testStatus, launchID: self.launchID ?? "")
    
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      print("✅ ReportingService: Test finished, signaling semaphore")
      finishTestSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("✅ ReportingService: Waiting for finish test semaphore...")
    let result = finishTestSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("✅ ReportingService: Finish test semaphore wait result: \(result)")
  }
  
  func finishTestSuite() throws {
    print("📂✅ ReportingService: Finishing test suite")
    guard let testSuiteID = testSuiteID else {
      print("❌ ReportingService: TestSuiteID not found when finishing test suite")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    print("📂✅ ReportingService: TestSuiteID: \(testSuiteID), Status: \(testSuiteStatus)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let finishTestSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: testSuiteID, status: testSuiteStatus, launchID: self.launchID ?? "")
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      print("📂✅ ReportingService: Test suite finished, signaling semaphore")
      finishTestSuiteSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("📂✅ ReportingService: Waiting for finish test suite semaphore...")
    let result = finishTestSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("📂✅ ReportingService: Finish test suite semaphore wait result: \(result)")
  }
  
  func finishRootSuite() throws {
    print("📁✅ ReportingService: Finishing root suite")
    guard let rootSuiteID = rootSuiteID else {
      print("❌ ReportingService: RootSuiteID not found when finishing root suite")
      throw ReportingServiceError.testSuiteIdNotFound
    }
    
    print("📁✅ ReportingService: RootSuiteID: \(rootSuiteID), Status: \(launchStatus)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let finishRootSuiteSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = try FinishItemEndPoint(itemID: rootSuiteID, status: launchStatus, launchID: self.launchID ?? "")
    try httpClient.callEndPoint(endPoint) { (result: Finish) in
      print("📁✅ ReportingService: Root suite finished, signaling semaphore")
      finishRootSuiteSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("📁✅ ReportingService: Waiting for finish root suite semaphore...")
    let result = finishRootSuiteSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("📁✅ ReportingService: Finish root suite semaphore wait result: \(result)")
  }
  
  func finishLaunch() throws {
    print("🎬✅ ReportingService: Finishing launch")
    guard configuration.shouldFinishLaunch else {
      print("🎬✅ ReportingService: Skip finish till next test bundle")
      return
    }
    guard let launchID = launchID else {
      print("❌ ReportingService: LaunchID not found when finishing launch")
      throw ReportingServiceError.launchIdNotFound
    }
    
    print("🎬✅ ReportingService: LaunchID: \(launchID), Status: \(launchStatus)")
    
    // Create INDIVIDUAL semaphore for this operation only
    let finishLaunchSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = FinishLaunchEndPoint(launchID: launchID, status: launchStatus)
    try httpClient.callEndPoint(endPoint) { (result: LaunchFinish) in
      print("🎬✅ ReportingService: Launch finished, signaling semaphore")
      finishLaunchSemaphore.signal()  // Signal THIS operation's semaphore
    }
    
    print("🎬✅ ReportingService: Waiting for finish launch semaphore...")
    let result = finishLaunchSemaphore.wait(timeout: .now() + timeOutForRequestExpectation)  // Wait on THIS operation's semaphore
    print("🎬✅ ReportingService: Finish launch semaphore wait result: \(result)")
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
  
}

extension String {
  var isLowercased: Bool {
    return lowercased() == self
  }
}
