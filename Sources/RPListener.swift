//
//  Listener.swift
//  com.oxagile.automation.RPAgentSwiftXCTest
//
//  Created by Windmill Smart Solutions on 5/12/17.
//  Enhanced for Gherkin integration without hard dependency
//

import Foundation
import XCTest

open class RPListener: NSObject, XCTestObservation {
  
    // MARK: - Singleton
    public static let shared = RPListener()

    public var reportingService: ReportingService?
    private let queue = DispatchQueue(label: "com.report_portal.reporting", qos: .utility)

    private override init() {
        super.init()
        XCTestObservationCenter.shared.addTestObserver(self)
    }
    
    /// Explicit bootstrap for test targets (call once early in test lifecycle)
    @discardableResult
    public static func register() -> RPListener {
        return RPListener.shared
    }
  
    // MARK: - Configuration
    private func readConfiguration(from testBundle: Bundle) -> AgentConfiguration {
        guard
            let bundlePath = testBundle.path(forResource: "RPConfig", ofType: "plist"),
            let bundleProperties = NSDictionary(contentsOfFile: bundlePath) as? [String: Any],
            let portalPath = bundleProperties["ReportPortalURL"] as? String,
            let portalURL = URL(string: portalPath),
            let projectName = bundleProperties["ReportPortalProjectName"] as? String,
            let token = bundleProperties["ReportPortalToken"] as? String,
            let shouldFinishLaunch = bundleProperties["IsFinalTestBundle"] as? Bool,
            let launchName = bundleProperties["ReportPortalLaunchName"] as? String else {
                fatalError("Configure properties for report portal in the RPConfig.plist")
        }
        
        let shouldReport: Bool
        if let pushTestDataString = bundleProperties["PushTestDataToReportPortal"] as? String {
            shouldReport = Bool(pushTestDataString.lowercased()) ?? false
        } else if let pushTestDataBool = bundleProperties["PushTestDataToReportPortal"] as? Bool {
            shouldReport = pushTestDataBool
        } else {
            fatalError("PushTestDataToReportPortal must be either a string or a boolean in the RPConfig.plist")
        }
        
        var tags: [String] = []
        if let tagString = bundleProperties["ReportPortalTags"] as? String {
            tags = tagString.trimmingCharacters(in: .whitespacesAndNewlines)
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
  
    // MARK: - XCTestObservation
  
    public func testBundleWillStart(_ testBundle: Bundle) {
        let configuration = readConfiguration(from: testBundle)
        
        guard configuration.shouldSendReport else {
            print("Set 'YES' for 'PushTestDataToReportPortal' in RPConfig.plist to enable reporting.")
            return
        }
        
        let reportingService = ReportingService(configuration: configuration, testBundle: testBundle)
        self.reportingService = reportingService
        
        queue.async {
            do {
                try reportingService.startLaunch()
            } catch {
                print("🚨 RPListener Launch Start Error: \(error.localizedDescription)")
            }
        }
    }
  
    public func testSuiteWillStart(_ testSuite: XCTestSuite) {
        guard let reportingService = reportingService else {
            print("🚨 RPListener: ReportingService missing. Suite '\(testSuite.name)' not reported.")
            return
        }
        
        guard !testSuite.name.contains("All tests"),
              !testSuite.name.contains("Selected tests") else {
            return
        }
        
        queue.async {
            do {
                // Ensure launch is started before starting suites (idempotent)
                try reportingService.startLaunch()
                if testSuite.name.contains(".xctest") {
                    try reportingService.startRootSuite(testSuite)
                } else {
                    try reportingService.startTestSuite(testSuite)
                }
            } catch {
                print("🚨 RPListener Suite Start Error: \(error.localizedDescription)")
            }
        }
    }

    public func testCaseWillStart(_ testCase: XCTestCase) {
        // Bootstrap reportingService if needed
        if reportingService == nil {
            let configBundle = Bundle(for: type(of: testCase))
            let configuration = readConfiguration(from: configBundle)

            guard configuration.shouldSendReport else {
                print("🚨 RPListener: Reporting disabled in config.")
                return
            }

            let service = ReportingService(configuration: configuration, testBundle: configBundle)
            self.reportingService = service

            do {
                try service.startLaunch() // sync launch start
            } catch {
                print("🚨 RPListener: Failed to start launch for \(testCase.name) — \(error.localizedDescription)")
            }
        }

        // Ensure launch is ready even if async start from testBundleWillStart hasn't finished
        if reportingService?.launchID == nil {
            do {
                try reportingService?.startLaunch()
            } catch {
                print("🚨 RPListener: Failed to ensure launch started — \(error.localizedDescription)")
            }
        }

        // ✅ Gherkin-specific suite initialization workaround
        ensureGherkinSuitesInitialized(for: testCase)

        // Unified Gherkin name extraction
        let (featureName, scenarioName) = extractGherkinNames(from: testCase)

        // Start the test
        do {
            try reportingService?.startTest(testCase, featureName: featureName, scenarioName: scenarioName)
        } catch {
            print("🚨 RPListener: Failed to start test case \(testCase.name) — \(error.localizedDescription)")
        }
    }

    // MARK: - Gherkin Suite Initialization Helper
    /// XCTest-Gherkin compatibility note:
    /// Normally, root/test suites are initialized in testSuiteWillStart.
    /// However, XCTest-Gherkin dynamically generates suites for scenarios with names
    /// like "All tests" or "Selected tests", which RPListener ignores.
    /// As a result, startRootSuite()/startTestSuite() is never called,
    /// leaving rootSuiteID/testSuiteID unset and causing startTest() to fail.
    ///
    /// This helper manually initializes suites if IDs are missing, ensuring
    /// proper ReportPortal hierarchy for Gherkin scenarios.
    private func ensureGherkinSuitesInitialized(for testCase: XCTestCase) {
        // Only apply this workaround when XCTest-Gherkin is present
        guard NSClassFromString("NativeTestCase") != nil || NSClassFromString("XCGNativeInitializer") != nil else { return }
        guard let reportingService = reportingService,
                reportingService.rootSuiteID == nil || reportingService.testSuiteID == nil else { return }
        
        print("🛠 RPListener: Initializing missing Gherkin suites for ReportPortal.")
        queue.sync {
            if reportingService.rootSuiteID == nil {
                try? reportingService.startRootSuite(XCTestSuite(name: "Gherkin Features"))
            }
            if reportingService.testSuiteID == nil {
                let suiteName = String(describing: type(of: testCase))
                try? reportingService.startTestSuite(XCTestSuite(name: suiteName))
            }
        }
    }

#if swift(>=5.9) // Swift 5.9 is shipped with Xcode 15 / iOS 17 SDK
    // Modern API (iOS 17+, Xcode 15+)
    @available(iOS 17.0, macOS 14.0, *)
    public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
            ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
            : ""
        let errorMessage = "Test '\(testCase.name)' failed\(lineNumberString), \(issue.description)"
        reportFailure(testCase: testCase, message: errorMessage)
    }
#else
    // Legacy API (pre-iOS 17, Xcode <15)
    public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssueReference) {
        let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
            ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
            : ""
        let errorMessage = "Test '\(testCase.name)' failed\(lineNumberString): \(issue.description)"
        reportFailure(testCase: testCase, message: errorMessage)
    }
#endif

    // Legacy API (very old XCTest)
    public func testCase(_ testCase: XCTestCase,
                         didFailWithDescription description: String,
                         inFile filePath: String?,
                         atLine lineNumber: Int) {
        let fileInfo = filePath != nil ? " in \(URL(fileURLWithPath: filePath!).lastPathComponent)" : ""
        let errorMessage = "Test failed on line \(lineNumber)\(fileInfo): \(description)"
        reportFailure(testCase: testCase, message: errorMessage)
    }

    // MARK: - Private helper
    private func reportFailure(testCase: XCTestCase, message: String) {
        guard let reportingService = reportingService else { return }
        
        queue.async {
            do {
                try reportingService.reportErrorWithScreenshot(message: message, testCase: testCase)
            } catch {
                print("🚨 RPListener Failure Reporting Error: \(error.localizedDescription)")
            }
        }
    }
  
    public func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let reportingService = reportingService else { return }

        queue.async {
            try? reportingService.finishTest(testCase)
        }
    }
  
    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let reportingService = reportingService else { return }
        
        guard !testSuite.name.contains("All tests"),
              !testSuite.name.contains("Selected tests") else {
            return
        }
        
        queue.async {
            if testSuite.name.contains(".xctest") {
                try? reportingService.finishRootSuite()
            } else {
                try? reportingService.finishTestSuite()
            }
        }
    }
  
    public func testBundleDidFinish(_ testBundle: Bundle) {
        guard let reportingService = reportingService else { return }

        queue.sync {
            try? reportingService.finishLaunch()
        }
    }

    // MARK: - Gherkin Detection & Name Extraction
    private func extractGherkinNames(from testCase: XCTestCase) -> (feature: String?, scenario: String?) {
        // Safety check: If neither NativeTestCase nor XCGNativeInitializer exists, skip
        guard NSClassFromString("NativeTestCase") != nil || NSClassFromString("XCGNativeInitializer") != nil else {
            return (nil, nil)
        }
        
        if let nativeTestCaseClass = NSClassFromString("NativeTestCase"),
           testCase.isKind(of: nativeTestCaseClass),
           let invocation = testCase.invocation {

            let selector = invocation.selector
            let featureScenarioDataSelector = NSSelectorFromString("featureScenarioData:")

            if (nativeTestCaseClass as AnyObject).responds(to: featureScenarioDataSelector),
                let unmanagedResult = (nativeTestCaseClass as AnyObject).perform(featureScenarioDataSelector, with: selector as Any) {
                let tupleAny = unmanagedResult.takeUnretainedValue()
                if let tuple = tupleAny as? (Any, Any) {
                    let featureName = (tuple.0 as? NSObject)?.value(forKey: "name") as? String
                    let scenarioName = (tuple.1 as? NSObject)?.value(forKey: "name") as? String
                    return (featureName, scenarioName)
                }
            }
        }

        if let gherkinBaseClass = NSClassFromString("XCGNativeInitializer"),
           testCase.isKind(of: gherkinBaseClass) {
            let featureName = String(describing: type(of: testCase))
            let scenarioName = parseScenarioName(from: testCase.name)
            return (featureName, scenarioName)
        }

        return (nil, nil)
    }

    private func parseScenarioName(from rawName: String) -> String {
        guard let methodPart = rawName.split(separator: " ").last else { return rawName }
        var cleaned = methodPart.replacingOccurrences(of: "]", with: "")
        if cleaned.hasPrefix("test") {
            cleaned.removeFirst("test".count)
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
