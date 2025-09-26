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
  public static let shared = RPListener()

  public var reportingService: ReportingService?
  private let queue = DispatchQueue(label: "com.report_portal.reporting", qos: .utility)

  private override init() {
    super.init()
    XCTestObservationCenter.shared.addTestObserver(self)
  }
    
//  /// Explicit bootstrap for test targets (call once early in test lifecycle)
//  @discardableResult
//  public static func register() -> RPListener {
//    return RPListener.shared
//  }
  
  private func readConfiguration(from testBundle: Bundle) -> AgentConfiguration {
    // 🔍 Debug helper: list all bundles and check for RPConfig.plist
    print("🔍 RPListener: Listing all loaded bundles and searching for RPConfig.plist...")
    for bundle in Bundle.allBundles {
      let hasConfig = bundle.path(forResource: "RPConfig", ofType: "plist") != nil
      print("   • Bundle: \(bundle.bundlePath) — RPConfig.plist: \(hasConfig ? "✅ found" : "❌ not found")")
    }

    func findConfigBundle() -> Bundle? {
      for bundle in Bundle.allBundles {
        if bundle.path(forResource: "RPConfig", ofType: "plist") != nil {
          return bundle
        }
      }
      return nil
    }

    var configBundle: Bundle? = testBundle
    if configBundle?.path(forResource: "RPConfig", ofType: "plist") == nil {
      print("⚠️ RPListener: RPConfig.plist not found in provided bundle: \(testBundle.bundlePath)")
      configBundle = findConfigBundle()
    }

    guard let bundlePath = configBundle?.path(forResource: "RPConfig", ofType: "plist"),
      let bundleProperties = NSDictionary(contentsOfFile: bundlePath) as? [String: Any],
      let portalPath = bundleProperties["ReportPortalURL"] as? String,
      let portalURL = URL(string: portalPath),
      let projectName = bundleProperties["ReportPortalProjectName"] as? String,
      let token = bundleProperties["ReportPortalToken"] as? String,
      let shouldFinishLaunch = bundleProperties["IsFinalTestBundle"] as? Bool,
      let launchName = bundleProperties["ReportPortalLaunchName"] as? String else
    {
      fatalError("❌ RPListener: Configure properties for ReportPortal in RPConfig.plist")
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
      tags = tagString.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        .components(separatedBy: ",")
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        .filter { !$0.isEmpty }
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
      print("Set 'YES' for 'PushTestDataToReportPortal' property in Info.plist if you want to put data to report portal")
      return
    }
    
    let reportingService = ReportingService(configuration: configuration, testBundle: testBundle)
    self.reportingService = reportingService
    do {
      try reportingService.startLaunch()
    } catch let error {
      print("🚨 RPListener Launch Start Error: Failed to start ReportPortal launch for test bundle. This will prevent all test results from being reported. Error details: \(error.localizedDescription)")
    }
  }
  
  public func testSuiteWillStart(_ testSuite: XCTestSuite) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test suite '\(testSuite.name)' will not be reported to ReportPortal.")
      return
    }
    // Skip NativeTestCase suites — handled by featureScenarioTest()
    if let nativeTestCaseClass = NSClassFromString("NativeTestCase"), suiteContainsNativeTestCase(testSuite, nativeClass: nativeTestCaseClass) {
      print("ℹ️ RPListener: Skipping startTestSuite for '\(testSuite.name)' — contains NativeTestCase")
      return
    }
    
    guard
      !testSuite.name.contains("All tests"),
      !testSuite.name.contains("Selected tests") else
    {
      return
    }
    
    queue.async {
      do {
        if testSuite.name.contains(".xctest") {
          try reportingService.startRootSuite(testSuite)
        } else {
          try reportingService.startTestSuite(testSuite)
        }
      } catch let error {
        print("🚨 RPListener Suite Start Error: Failed to start test suite '\(testSuite.name)' in ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }

  public func testCaseWillStart(_ testCase: XCTestCase) {
    if let nativeTestCaseClass = NSClassFromString("NativeTestCase"), testCase.isKind(of: nativeTestCaseClass) {
      print("ℹ️ RPListener: Skipping startTest for \(testCase.name) — handled by NativeTestCase")
      return
    }
    if let nativeTestCaseClass = NSClassFromString("XCTest_Gherkin.NativeTestCase"), testCase.isKind(of: nativeTestCaseClass) {
      print("ℹ️ RPListener: Skipping startTest for \(testCase.name) — handled by NativeTestCase.featureScenarioTest()")
      return
    }
    // Bootstrap reportingService if needed
    if reportingService == nil {
      print("⚠️ RPListener: reportingService is nil — initializing now")
      let configBundle = Bundle.main // or scan all bundles for RPConfig.plist
      let configuration = readConfiguration(from: configBundle)
      guard configuration.shouldSendReport else {
        print("🚨 RPListener: Reporting disabled in config.")
        return
      }
      let service = ReportingService(configuration: configuration, testBundle: configBundle)
      reportingService = service
      try? service.startLaunch()
    }

    guard let service = reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test case '\(testCase.name)' will not be reported to ReportPortal.")
      return
    }

    // Ensure launch started
    if service.launchID == nil {
      try? service.startLaunch()
    }

    // Ensure root suite started
    if service.rootSuiteID == nil {
      try? service.startRootSuite(XCTestSuite(name: "Default Root Suite"))
    }

    // Ensure test suite started
    if service.testSuiteID == nil {
      let suiteName = String(describing: type(of: testCase))
      try? service.startTestSuite(XCTestSuite(name: suiteName))
    }

    queue.async {
      do {
        try service.startTest(testCase)
      } catch let error {
        print("🚨 RPListener Test Start Error: Failed to start test case '\(testCase.name)' in ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }

  @available(*, deprecated, message: "Use fun public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) for iOs 17+")
  public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssueReference) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test issue for '\(testCase.name)' will not be reported to ReportPortal.")
      return
    }

    queue.async {
      do {
        let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
          ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
          : ""
        let errorMessage = "Test '\(String(describing: issue.description))' failed\(lineNumberString), \(issue.description)"

        try reportingService.reportErrorWithScreenshot(message: errorMessage, testCase: testCase)
      } catch let error {
        print("🚨 RPListener Issue Reporting Error: Failed to report test issue for '\(testCase.name)' to ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }

  // For iOs 17+
  public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test failure for '\(testCase.name)' will not be reported to ReportPortal.")
      return
    }

    queue.async {
      do {
        let fileInfo = filePath != nil ? " in \(URL(fileURLWithPath: filePath!).lastPathComponent)" : ""
        let errorMessage = "Test failed on line \(lineNumber)\(fileInfo): \(description)"
        
        try reportingService.reportErrorWithScreenshot(message: errorMessage, testCase: testCase)
      } catch let error {
        print("🚨 RPListener Failure Reporting Error: Failed to report test failure for '\(testCase.name)' to ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }
  
  public func testCaseDidFinish(_ testCase: XCTestCase) {
    // Detect NativeTestCase (module-qualified or not)
    if String(describing: type(of: testCase)).contains("NativeTestCase") {
      guard let service = reportingService else {
        print("🚨 RPListener: ReportingService is not available. Cannot finish NativeTestCase '\(testCase.name)'")
        return
      }
      let passed = testCase.testRun?.hasSucceeded ?? true
      let status = passed ? "passed" : "failed"
      print("ℹ️ RPListener: NativeTestCase '\(testCase.name)' finished with status: \(status)")
      queue.async {
        try? service.finishTest(testCase, status: status)
      }
      return
    }

    guard let reportingService = reportingService else { return }

    queue.async {
      do {
        try reportingService.finishTest(testCase)
      } catch let error {
        print("🚨 RPListener Test Finish Error: Failed to finish test case '\(testCase.name)' in ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }
  
  public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test suite completion for '\(testSuite.name)' will not be reported to ReportPortal.")
      return
    }

    if let nativeTestCaseClass = NSClassFromString("NativeTestCase"), suiteContainsNativeTestCase(testSuite, nativeClass: nativeTestCaseClass) {
      print("ℹ️ RPListener: Skipping startTestSuite for '\(testSuite.name)' — contains NativeTestCase")
      return
    }
    
    guard
      !testSuite.name.contains("All tests"),
      !testSuite.name.contains("Selected tests") else
    {
      return
    }
    
    queue.async {
      do {
        if testSuite.name.contains(".xctest") {
          try reportingService.finishRootSuite()
        } else {
          try reportingService.finishTestSuite()
        }
      } catch let error {
        print("🚨 RPListener Suite Finish Error: Failed to finish test suite '\(testSuite.name)' in ReportPortal. Error details: \(error.localizedDescription)")
      }
    }
  }
  
  public func testBundleDidFinish(_ testBundle: Bundle) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test bundle completion will not be reported to ReportPortal.")
      return
    }

    queue.sync() {
      do {
        try reportingService.finishLaunch()
      } catch let error {
        print("🚨 RPListener Launch Finish Error: Failed to finish ReportPortal launch for test bundle. Error details: \(error.localizedDescription)")
      }
    }
  }
    
  private func suiteContainsNativeTestCase(_ suite: XCTestSuite, nativeClass: AnyClass) -> Bool {
    for test in suite.tests {
      if test.isKind(of: nativeClass) { return true }
      if let childSuite = test as? XCTestSuite,
        suiteContainsNativeTestCase(childSuite, nativeClass: nativeClass) {
        return true
      }
    }
    return false
  }
}

private let _rpListenerBootstrap = RPListener.shared
