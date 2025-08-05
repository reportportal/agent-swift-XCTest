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
    do {
      try httpClient.callEndPoint(endPoint) { (result: LaunchListInfo) in
        guard let launch = result.content.first, launch.status == "IN_PROGRESS" else {
          completion(nil)
          return
        }
        
        completion(launch.uuid)
      }
    } catch {
      print("⚠️ ReportingService: Failed to get stored launch ID: \(error.localizedDescription)")
      completion(nil) // Call completion with nil to prevent deadlock
    }
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
  
  func reportError(message: String) throws {
    guard !testID.isEmpty else {
      print("🚨 ReportingService Error Reporting Failed: Cannot report error '\(message)' - Test ID is missing. This indicates test creation failed. Error will not appear in ReportPortal.")
      return
    }
    
    let errorSemaphore = DispatchSemaphore(value: 0)
    
    let endPoint = PostLogEndPoint(itemID: testID, level: "error", message: message)
    do {
      try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
        errorSemaphore.signal()
      }
    } catch {
      print("⚠️ ReportingService: Failed to report error: \(error.localizedDescription)")
      errorSemaphore.signal() // Signal to prevent deadlock
      throw error
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
    
    do {
      try httpClient.callEndPoint(endPoint) { (result: LogResponse) in
        print("✅ ReportingService Debug: Log API responded with success")
        print("   • Response: \(result)")
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
        
        // Enhanced stack trace with more context
        let stackTrace = Thread.callStackSymbols
        if stackTrace.count > 1 {
            enhancedMessage += "\nStack Trace\n"
            enhancedMessage += "-----------\n"
            
            // Find the first test-related frame
            var testFrameIndex = -1
            for (index, frame) in stackTrace.enumerated() {
                if frame.contains("test") || frame.contains("Test") {
                    testFrameIndex = index
                    break
                }
            }
            
            // Include frames starting from the test method or from frame 3
            let startIndex = testFrameIndex >= 0 ? testFrameIndex : 3
            let relevantFrames = stackTrace.dropFirst(startIndex).prefix(8)
            
            var frameNumber = 0
            for frame in relevantFrames {
                if let enhancedFrame = enhanceStackFrame(frame) {
                    frameNumber += 1
                    enhancedMessage += "\n\(frameNumber). \(sanitizeForJSON(enhancedFrame.description))\n"
                    
                    // Only show module if it's not the test framework itself
                    if !enhancedFrame.module.isEmpty && 
                       !enhancedFrame.module.contains("ReportPortalAgent") && 
                       !enhancedFrame.module.contains("XCTest") {
                        enhancedMessage += "   Module: \(sanitizeForJSON(enhancedFrame.module))\n"
                    }
                    
                    // Show method details if available and meaningful
                    if !enhancedFrame.function.isEmpty && 
                       enhancedFrame.function != enhancedFrame.description {
                        enhancedMessage += "   Method: \(sanitizeForJSON(enhancedFrame.function))\n"
                    }
                    
                    if enhancedFrame.lineNumber > 0 {
                        enhancedMessage += "   Line: \(enhancedFrame.lineNumber)\n"
                    }
                }
            }
            
            if frameNumber == 0 {
                enhancedMessage += "   (No relevant stack frames available)\n"
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
    
    // Structure to hold enhanced stack frame information
    private struct StackFrameInfo {
        let description: String
        let module: String
        let function: String
        let lineNumber: Int
    }
    
    // Helper to enhance stack frame with more details
    private func enhanceStackFrame(_ frame: String) -> StackFrameInfo? {
        // Validate input
        guard !frame.isEmpty, frame.count < 5000 else { return nil } // Prevent processing extremely long strings
        
        // Stack frame format: "0   ModuleName   0x... functionName + offset"
        let components = frame.split(separator: " ", maxSplits: 20, omittingEmptySubsequences: true).map(String.init)
        
        guard components.count >= 3 else { return nil }
        
        var module = ""
        var function = ""
        var lineNumber = 0
        var description = ""
        
        // Find module name (usually at index 1)
        if components.indices.contains(1) {
            let potentialModule = components[1]
            // Additional validation for module name
            if !potentialModule.starts(with: "0x") && 
               !potentialModule.allSatisfy({ $0.isNumber }) &&
               potentialModule.count < 100 { // Reasonable module name length
                module = String(potentialModule.prefix(50)) // Limit module name length
            }
        }
        
        // Look for function name (after memory address)
        var functionStartIndex = -1
        for (index, component) in components.enumerated() where index < 10 { // Limit search range
            if component.starts(with: "0x") {
                functionStartIndex = index + 1
                break
            }
        }
        
        if functionStartIndex > 0 && functionStartIndex < components.count && functionStartIndex < 15 {
            // Extract function name and clean it up
            var functionComponents: [String] = []
            let endIndex = min(functionStartIndex + 10, components.count) // Limit function components
            for i in functionStartIndex..<endIndex {
                let component = components[i]
                if component == "+" { break }  // Stop at offset marker
                if component.count < 200 { // Reasonable component length
                    functionComponents.append(component)
                }
            }
            
            function = functionComponents.prefix(5).joined(separator: " ")
            
            // Limit function length before processing
            function = String(function.prefix(200))
            
            // Clean up function name
            function = function.replacingOccurrences(of: "$s", with: "")  // Swift mangling prefix
            function = function.replacingOccurrences(of: "$S", with: "")
            
            // Try to demangle Swift function names
            if function.contains("$") && function.count < 150 {
                // Basic demangling for common patterns
                function = demangleSwiftName(function)
            }
        }
        
        // Extract line number if present (with safety bounds)
        if frame.count < 2000 { // Only search in reasonably sized strings
            if let lineMatch = frame.range(of: #":\d{1,5}"#, options: .regularExpression) {
                let lineStr = String(frame[lineMatch]).dropFirst() // Remove ":"
                lineNumber = Int(lineStr) ?? 0
                if lineNumber > 999999 { lineNumber = 0 } // Sanity check
            }
        }
        
        // Create a human-readable description focusing on the most relevant information
        if function.contains("test") && !function.isEmpty {
            // For test methods, simplify the display
            description = String(function.prefix(100))
                .replacingOccurrences(of: "-[", with: "")
                .replacingOccurrences(of: "]", with: "")
                .replacingOccurrences(of: " ", with: ".")
        } else if !module.isEmpty && !function.isEmpty {
            // For regular methods, show module.function format
            let safeModule = String(module.prefix(50))
            let safeFunction = String(function.prefix(100))
            description = "\(safeModule).\(safeFunction)"
        } else if !function.isEmpty {
            description = String(function.prefix(100))
        } else if !module.isEmpty {
            description = String(module.prefix(50))
        } else {
            // Fall back to the most informative part we can find
            description = components.first(where: { 
                !$0.starts(with: "0x") && 
                !$0.allSatisfy({ $0.isNumber }) && 
                $0.count < 100 
            }) ?? "Unknown"
        }
        
        // Limit final description length
        description = String(description.prefix(200))
        
        // Add context indicators for special frameworks
        if function.contains("test") || module.contains("Test") {
            description = "🧪 " + description
        } else if module.contains("XCTest") {
            description = "🔧 " + description
        } else if module.contains("UIKit") || module.contains("CoreGraphics") {
            description = "📱 " + description
        } else if module == "libdispatch.dylib" || module.contains("queue") {
            description = "⚡ " + description
        }
        
        return StackFrameInfo(
            description: description,
            module: module,
            function: function,
            lineNumber: lineNumber
        )
    }
    
    // Basic Swift name demangling (with safety checks)
    private func demangleSwiftName(_ mangledName: String) -> String {
        // Safety check: limit input length
        guard mangledName.count < 500 else { return String(mangledName.prefix(200)) }
        
        var demangled = mangledName
        
        // Common Swift mangling patterns (limit replacements to prevent excessive processing)
        let replacements = [
            ("ySS", "String"),
            ("ySi", "Int"),
            ("ySb", "Bool"),
            ("yXl", "Error"),
            ("tF", "."),
            ("fC", ".")
        ]
        
        for (pattern, replacement) in replacements {
            // Only replace if the result won't be too long
            let potential = demangled.replacingOccurrences(of: pattern, with: replacement)
            if potential.count < 300 {
                demangled = potential
            }
        }
        
        // Remove common prefixes
        if demangled.hasPrefix("_T") {
            demangled = String(demangled.dropFirst(2))
        }
        
        // Final length limit
        return String(demangled.prefix(200))
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
        // If we have a test plan name, include it in the launch name like Android does
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

