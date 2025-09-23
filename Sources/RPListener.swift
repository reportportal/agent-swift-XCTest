//
//  Listener.swift
//  com.oxagile.automation.RPAgentSwiftXCTest
//
//  Created by Windmill Smart Solutions on 5/12/17.
//  Enhanced for Gherkin integration without hard dependency
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
  
  private func readConfiguration(from testBundle: Bundle) -> AgentConfiguration {
    guard
      let bundlePath = testBundle.path(forResource: "RPConfig", ofType: "plist"),
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
    
    queue.async {
      do {
        try reportingService.startLaunch()
      } catch let error {
        print("🚨 RPListener Launch Start Error: Failed to start ReportPortal launch for test bundle. This will prevent all test results from being reported. Error details: \(error.localizedDescription)")
      }
    }
  }
  
  public func testSuiteWillStart(_ testSuite: XCTestSuite) {
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test suite '\(testSuite.name)' will not be reported to ReportPortal.")
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
        // If no reportingService yet, bootstrap it synchronously
        if reportingService == nil {
            let configBundle = Bundle(for: type(of: testCase))
            let configuration = readConfiguration(from: configBundle)

            guard configuration.shouldSendReport else {
                print("🚨 RPListener: Reporting disabled in config.")
                return
            }

            let service = ReportingService(configuration: configuration, testBundle: configBundle)
            self.reportingService = service

            // Synchronous launch start to ensure launchID is ready before startTest
            do {
                try service.startLaunch()
            } catch {
                print("🚨 RPListener: Failed to start launch for \(testCase.name) — \(error.localizedDescription)")
            }
        }

        // Ensure root suite is started
        if reportingService?.rootSuiteID == nil {
            do {
                try reportingService?.startRootSuite(XCTestSuite(name: "Gherkin Features"))
            } catch {
                print("🚨 RPListener: Failed to start root suite — \(error.localizedDescription)")
            }
        }

        // Ensure test suite is started
        if reportingService?.testSuiteID == nil {
            let suiteName: String
            if let nativeClass = NSClassFromString("NativeTestCase"),
               testCase.isKind(of: nativeClass) {
                suiteName = String(describing: type(of: testCase))
            } else {
                suiteName = "Default Suite"
            }
            do {
                try reportingService?.startTestSuite(XCTestSuite(name: suiteName))
            } catch {
                print("🚨 RPListener: Failed to start test suite — \(error.localizedDescription)")
            }
        }

        // Extract feature/scenario names dynamically
        var featureName: String? = nil
        var scenarioName: String? = nil
        if let nativeTestCaseClass = NSClassFromString("NativeTestCase"),
           testCase.isKind(of: nativeTestCaseClass),
           let invocation = testCase.invocation {

            let selector = invocation.selector
            let featureScenarioDataSelector = NSSelectorFromString("featureScenarioData:")

            if nativeTestCaseClass.responds(to: featureScenarioDataSelector),
               let unmanagedResult = (nativeTestCaseClass as AnyObject).perform(featureScenarioDataSelector, with: selector as Any) {

                let tupleAny = unmanagedResult.takeUnretainedValue()
                if let tuple = tupleAny as? (Any, Any) {
                    if let featureObj = tuple.0 as? NSObject,
                       let fname = featureObj.value(forKey: "name") as? String {
                        featureName = fname
                    }
                    if let scenarioObj = tuple.1 as? NSObject,
                       let sname = scenarioObj.value(forKey: "name") as? String {
                        scenarioName = sname
                    }
                }
            }
        }

        // Start the test
        do {
            try reportingService?.startTest(testCase, featureName: featureName, scenarioName: scenarioName)
        } catch {
            print("🚨 RPListener: Failed to start test case \(testCase.name) — \(error.localizedDescription)")
        }
    }

  @available(*, deprecated, message: "Use func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) for iOS 17+")
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

  // For iOS 17+
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
    guard let reportingService = self.reportingService else {
      print("🚨 RPListener Configuration Error: ReportingService is not available. Test completion for '\(testCase.name)' will not be reported to ReportPortal.")
      return
    }

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

    queue.sync {
      do {
        try reportingService.finishLaunch()
      } catch let error {
        print("🚨 RPListener Launch Finish Error: Failed to finish ReportPortal launch for test bundle. Error details: \(error.localizedDescription)")
      }
    }
  }

  // MARK: - Gherkin Detection & Name Extraction (No hard dependency)
  private func extractGherkinNames(from testCase: XCTestCase) -> (feature: String?, scenario: String?) {
    if let gherkinBaseClass = NSClassFromString("XCGNativeInitializer"),
       testCase.isKind(of: gherkinBaseClass) {
      
      let featureName = String(describing: type(of: testCase))
      let scenarioName = parseScenarioName(from: testCase.name)
      return (featureName, scenarioName)
    }
    return (nil, nil)
  }

  private func parseScenarioName(from rawName: String) -> String {
    // rawName example: "-[MyFeatureTests testScenario_1]"
    guard let methodPart = rawName.split(separator: " ").last else { return rawName }
    var cleaned = methodPart.replacingOccurrences(of: "]", with: "")
    if cleaned.hasPrefix("test") {
      cleaned.removeFirst("test".count)
    }
    cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
    return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
