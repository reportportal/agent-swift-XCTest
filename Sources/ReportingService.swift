//
//  RPServices.swift
//
//  Created by Stas Kirichok on 22/08/18.
//  Copyright © 2018 Windmill. All rights reserved.
//

import Foundation
import XCTest

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
      
      print("🔍 ReportingService: Found existing launch with ID: \(launch.uuid)")
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
