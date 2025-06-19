//
//  Listener.swift
//  com.oxagile.automation.RPAgentSwiftXCTest
//
//  Created by Windmill Smart Solutions on 5/12/17.
//  Copyright © 2017 Oxagile. All rights reserved.
//

import Foundation
import XCTest

open class RPListener: NSObject, XCTestObservation {
  
  public var reportingService: ReportingService?
  private let queue = DispatchQueue(label: "com.report_portal.reporting", qos: .utility)
  
  public override init() {
    super.init()
    
    XCTestObservationCenter.shared.addTestObserver(self)
  }
  
  private func readConfiguration(from testBundle: Bundle) -> AgentConfiguration {
    guard
      let bundlePath = testBundle.path(forResource: "Info", ofType: "plist"),
      let bundleProperties = NSDictionary(contentsOfFile: bundlePath) as? [String: Any],
      let portalPath = bundleProperties["ReportPortalURL"] as? String,
      let portalURL = URL(string: portalPath),
      let projectName = bundleProperties["ReportPortalProjectName"] as? String,
      let token = bundleProperties["ReportPortalToken"] as? String,
      let shouldFinishLaunch = bundleProperties["IsFinalTestBundle"] as? Bool,
      let launchName = bundleProperties["ReportPortalLaunchName"] as? String else
    {
      fatalError("Configure properties for report portal in the Info.plist")
    }
    
    let shouldReport: Bool
    if let pushTestDataString = bundleProperties["PushTestDataToReportPortal"] as? String {
        shouldReport = Bool(pushTestDataString.lowercased()) ?? false
    } else if let pushTestDataBool = bundleProperties["PushTestDataToReportPortal"] as? Bool {
        shouldReport = pushTestDataBool
    } else {
        fatalError("PushTestDataToReportPortal must be either a string or a boolean in the Info.plist")
    }
    
    var tags: [String] = []
    if let tagString = bundleProperties["ReportPortalTags"] as? String {
      tags = tagString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines).components(separatedBy: ",")
    }
    var launchMode: LaunchMode = .default
    if let isDebug = bundleProperties["IsDebugLaunchMode"] as? Bool, isDebug == true {
      launchMode = .debug
    }

    var testNameRules: NameRules = []
    if let rules = bundleProperties["TestNameRules"] as? [String: Bool] {
      if rules["StripTestPrefix"] == true {
        testNameRules.update(with: .stripTestPrefix)
      }
      if rules["WhiteSpaceOnUnderscore"] == true {
        testNameRules.update(with: .whiteSpaceOnUnderscore)
      }
      if rules["WhiteSpaceOnCamelCase"] == true {
        testNameRules.update(with: .whiteSpaceOnCamelCase)
      }
    }
    
    return AgentConfiguration(
      reportPortalURL: portalURL,
      projectName: projectName,
      launchName: launchName,
      shouldSendReport: shouldReport,
      portalToken: token,
      tags: tags,
      shouldFinishLaunch: shouldFinishLaunch,
      launchMode: launchMode,
      testNameRules: testNameRules
    )
  }
  
  public func testBundleWillStart(_ testBundle: Bundle) {
    let configuration = readConfiguration(from: testBundle)
    
    guard configuration.shouldSendReport else {
      return
    }
    
    let reportingService = ReportingService(configuration: configuration)
    self.reportingService = reportingService
    
    queue.async {
      do {
        try reportingService.startLaunch()
      } catch let error {
        print("📦 RPListener: Error starting launch: \(error)")
      }
    }
  }
  
  public func testSuiteWillStart(_ testSuite: XCTestSuite) {
    print("📁 RPListener: testSuiteWillStart: '\(testSuite.name)' - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("📁 RPListener: No reportingService available")
      return 
    }
    
    guard
      !testSuite.name.contains("All tests"),
      !testSuite.name.contains("Selected tests") else
    {
      print("📁 RPListener: Skipping suite: \(testSuite.name)")
      return
    }
    
    print("📁 RPListener: Dispatching suite start to queue")
    queue.async {
      print("📁 RPListener: In queue - starting suite: \(testSuite.name) - Thread: \(Thread.current)")
      do {
        if testSuite.name.contains(".xctest") {
          print("📁 RPListener: Starting as root suite")
          try reportingService.startRootSuite(testSuite)
        } else {
          print("📁 RPListener: Starting as test suite")
          try reportingService.startTestSuite(testSuite)
        }
        print("📁 RPListener: Suite started successfully")
      } catch let error {
        print("📁 RPListener: Error starting suite: \(error)")
      }
    }
    print("📁 RPListener: testSuiteWillStart completed")
  }

  public func testCaseWillStart(_ testCase: XCTestCase) {
    print("🧪 RPListener: testCaseWillStart: '\(testCase.name)' - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("🧪 RPListener: No reportingService available")
      return 
    }

    print("🧪 RPListener: Dispatching test start to queue")
    queue.async {
      print("🧪 RPListener: In queue - starting test: \(testCase.name) - Thread: \(Thread.current)")
      do {
        try reportingService.startTest(testCase)
        print("🧪 RPListener: Test started successfully")
      } catch let error {
        print("🧪 RPListener: Error starting test: \(error)")
      }
    }
    print("🧪 RPListener: testCaseWillStart completed")
  }

  @available(*, deprecated, message: "Use fun public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) for iOs 17+")
  public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssueReference) {
    print("🚨 RPListener: testCase didRecord issue - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("🚨 RPListener: No reportingService available")
      return 
    }

    print("🚨 RPListener: Dispatching error report to queue")
    queue.async {
      print("🚨 RPListener: In queue - reporting error - Thread: \(Thread.current)")
      do {
        let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
          ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
          : ""
        let errorMessage = "Test '\(String(describing: issue.description))' failed\(lineNumberString), \(issue.description)"

        // Use enhanced error reporting with screenshot
        try reportingService.reportErrorWithScreenshot(message: errorMessage, testCase: testCase)
        print("🚨 RPListener: Error reported successfully")
      } catch let error {
        print("🚨 RPListener: Error reporting error: \(error)")
      }
    }
  }

  // For iOs 17+
  public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
    print("🚨 RPListener: testCase didFailWithDescription - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("🚨 RPListener: No reportingService available")
      return 
    }

    print("🚨 RPListener: Dispatching error report to queue")
    queue.async {
      print("🚨 RPListener: In queue - reporting error - Thread: \(Thread.current)")
      do {
        let fileInfo = filePath != nil ? " in \(URL(fileURLWithPath: filePath!).lastPathComponent)" : ""
        let errorMessage = "Test failed on line \(lineNumber)\(fileInfo): \(description)"
        
        // Use enhanced error reporting with screenshot  
        try reportingService.reportErrorWithScreenshot(message: errorMessage, testCase: testCase)
        print("🚨 RPListener: Error reported successfully")
      } catch let error {
        print("🚨 RPListener: Error reporting error: \(error)")
      }
    }
  }
  
  public func testCaseDidFinish(_ testCase: XCTestCase) {
    print("✅ RPListener: testCaseDidFinish: '\(testCase.name)' - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("✅ RPListener: No reportingService available")
      return 
    }

    print("✅ RPListener: Dispatching test finish to queue")
    queue.async {
      print("✅ RPListener: In queue - finishing test: \(testCase.name) - Thread: \(Thread.current)")
      do {
        try reportingService.finishTest(testCase)
        print("✅ RPListener: Test finished successfully")
      } catch let error {
        print("✅ RPListener: Error finishing test: \(error)")
      }
    }
    print("✅ RPListener: testCaseDidFinish completed")
  }
  
  public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
    print("📁✅ RPListener: testSuiteDidFinish: '\(testSuite.name)' - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("📁✅ RPListener: No reportingService available")
      return 
    }
    
    guard
      !testSuite.name.contains("All tests"),
      !testSuite.name.contains("Selected tests") else
    {
      print("📁✅ RPListener: Skipping suite finish: \(testSuite.name)")
      return
    }
    
    print("📁✅ RPListener: Dispatching suite finish to queue")
    queue.async {
      print("📁✅ RPListener: In queue - finishing suite: \(testSuite.name) - Thread: \(Thread.current)")
      do {
        if testSuite.name.contains(".xctest") {
          print("📁✅ RPListener: Finishing as root suite")
          try reportingService.finishRootSuite()
        } else {
          print("📁✅ RPListener: Finishing as test suite")
          try reportingService.finishTestSuite()
        }
        print("📁✅ RPListener: Suite finished successfully")
      } catch let error {
        print("📁✅ RPListener: Error finishing suite: \(error)")
      }
    }
    print("📁✅ RPListener: testSuiteDidFinish completed")
  }
  
  public func testBundleDidFinish(_ testBundle: Bundle) {
    print("📦✅ RPListener: testBundleDidFinish - Thread: \(Thread.current)")
    guard let reportingService = self.reportingService else { 
      print("📦✅ RPListener: No reportingService available")
      return 
    }

    print("📦✅ RPListener: Using queue.sync for launch finish")
    queue.sync() {
      print("📦✅ RPListener: In queue - finishing launch - Thread: \(Thread.current)")
      do {
        try reportingService.finishLaunch()
        print("📦✅ RPListener: Launch finished successfully")
      } catch let error {
        print("📦✅ RPListener: Error finishing launch: \(error)")
      }
    }
    print("📦✅ RPListener: testBundleDidFinish completed")
  }
}
