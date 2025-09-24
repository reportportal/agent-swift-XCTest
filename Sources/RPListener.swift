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
    
    /// Ensures the RPListener singleton is initialized and registered with XCTest, returning the shared instance.
    /// 
    /// Calling this method is safe to repeat; it simply returns the already-initialized shared RPListener and
    /// serves as an explicit bootstrap entry point for the listener.
    /// - Returns: The shared RPListener instance.
    @discardableResult
    public static func register() -> RPListener {
        return RPListener.shared
    }
  
    /// Reads ReportPortal settings from `RPConfig.plist` inside the provided test bundle and returns an assembled `AgentConfiguration`.
    /// 
    /// Reads required keys (ReportPortalURL, ReportPortalProjectName, ReportPortalToken, IsFinalTestBundle, ReportPortalLaunchName)
    /// and constructs an `AgentConfiguration` containing URL, project name, launch name, token, tags, launch behavior, and test-name rules.
    /// 
    /// The plist key `PushTestDataToReportPortal` may be either a String (case-insensitive `"true"`/`"false"`) or a Bool; otherwise this function calls `fatalError`.
    /// `ReportPortalTags`, if present as a comma-separated String, is split, trimmed, and empty entries are discarded.
    /// `IsDebugLaunchMode` toggles the returned `launchMode` between `.debug` and `.default`.
    /// `TestNameRules`, if provided as `[String: Bool]`, maps the following keys to `NameRules` flags:
    /// - "StripTestPrefix" -> `.stripTestPrefix`
    /// - "WhiteSpaceOnUnderscore" -> `.whiteSpaceOnUnderscore`
    /// - "WhiteSpaceOnCamelCase" -> `.whiteSpaceOnCamelCase`
    ///
    /// - Parameter testBundle: The test bundle in which `RPConfig.plist` is expected to reside.
    /// - Returns: A populated `AgentConfiguration` reflecting the plist values (and defaults where applicable).
    /// - Note: Missing any required key listed above will terminate execution via `fatalError` with an instruction to configure `RPConfig.plist`.
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
  
    /// Notifies the listener that a test bundle is about to start, reads RPConfig.plist from the bundle, and initializes the reporting lifecycle.
    ///
    /// If the configuration indicates reporting is disabled, the method logs a short instruction and returns. Otherwise it creates and stores a ReportingService for the bundle and asynchronously starts the launch.
    ///
    /// - Parameters:
    ///   - testBundle: The bundle for the running tests; used to load RPConfig.plist and derive the agent configuration.
  
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
  
    /// Called when an XCTestSuite is about to start; enqueues reporting actions to start the launch and the appropriate suite in the reporting service.
    /// 
    /// If no `reportingService` is configured the suite is not reported. Suites whose names contain `"All tests"` or `"Selected tests"` are ignored.
    /// The actual calls to `startLaunch()`, `startRootSuite(_:)`, or `startTestSuite(_:)` are performed asynchronously on the listener's internal queue; errors from the reporting service are caught and logged.
    ///
    /// - Parameter testSuite: The XCTestSuite that is starting; if its name contains `".xctest"` a root suite will be started, otherwise a regular test suite will be started.
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

    /// Called when an individual test case is about to run.
    /// 
    /// If the reporting service is not yet initialized this will bootstrap it from the test case's bundle and ensure a launch is started. It also performs Gherkin-related suite initialization, extracts optional feature and scenario names from the test case, and requests the reporting service to start the test run.
    /// - Parameter testCase: The XCTestCase instance that is starting; its bundle and runtime metadata are used to initialize reporting and to derive optional Gherkin feature/scenario names.
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
    /// Ensures ReportPortal root and test suites exist for Gherkin-style tests, creating any missing suites.
/// 
/// This is a compatibility workaround for XCTest-Gherkin integrations: when XCTest-Gherkin types are
/// present and the ReportingService lacks a root or test suite ID, the method synchronously creates
/// a "Gherkin Features" root suite and a test suite named after the test case's type.
/// - Parameters:
///   - testCase: The running XCTestCase whose type is used to name the test suite if one must be created.
    private func ensureGherkinSuitesInitialized(for testCase: XCTestCase) {
        private /// Ensure Gherkin test-suite hierarchy exists in the reporting service for the given test case.
    /// 
    /// When XCTest-Gherkin integration is present, this creates a missing root suite ("Gherkin Features")
    /// and/or a missing test suite named after the test case's dynamic type, so ReportPortal receives the
    /// expected feature/scenario structure. The operation is performed synchronously on the listener's
    /// internal reporting queue and is a no-op if the reporting service is absent or both suites are already initialized.
    /// A brief diagnostic message is printed when initialization is performed.
    func ensureGherkinSuitesInitialized(for testCase: XCTestCase) {
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

    // Modern API (iOS 17+, Xcode 15+)
    public /// Reports an `XCTIssue` for a running test to the configured reporting service.
    /// 
    /// Constructs a failure message including the test name and, if available, the source line number,
    /// and asynchronously forwards it to `reportFailure(testCase:message:)`. No-op if no reporting service is configured.
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssue) {
        guard let reportingService = reportingService else { return }

        queue.async {
            do {
                let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
                    ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
                    : ""
                let errorMessage = "Test '\(testCase.name)' failed\(lineNumberString), \(issue.description)"
                reportFailure(testCase: testCase, message: errorMessage)
            } catch {
                print("🚨 RPListener Issue Reporting Error: \(error.localizedDescription)")
            }
        }
    }

    // Legacy API (pre-iOS 17, Xcode <15)
    public /// Called when the test case records an `XCTIssueReference`. Reports the issue as a test failure to the reporting service, including source line information when available.
    /// - Parameters:
    ///   - testCase: The test case that recorded the issue.
    ///   - issue: The recorded issue reference; its `sourceCodeContext` line number (if present) is included in the reported message.
    func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssueReference) {
        let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
            ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
            : ""
        let errorMessage = "Test '\(testCase.name)' failed\(lineNumberString): \(issue.description)"
        
        reportFailure(testCase: testCase, message: errorMessage)
    }

    // Legacy API (pre-iOS 17, Xcode < 15)
    public /// Handles an XCTest legacy failure callback by formatting a single-line failure message (including file name when available) and delegating to `reportFailure(testCase:message:)`.
    /// - Note: `filePath` may be `nil`; when it's `nil` the file context is omitted from the formatted message.
    func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        let fileInfo = filePath != nil ? " in \(URL(fileURLWithPath: filePath!).lastPathComponent)" : ""
        let errorMessage = "Test failed on line \(lineNumber)\(fileInfo): \(description)"
        
        reportFailure(testCase: testCase, message: errorMessage)
    }

    // MARK: - Private helper
    private /// Reports a test failure to the configured reporting service, including a screenshot.
    /// - If no reporting service is configured, the call is a no-op.
    /// - The report is performed asynchronously on the listener's internal reporting queue; any errors from the reporting service are caught and printed.
    /// - Parameters:
    ///   - testCase: The XCTestCase instance associated with the failure.
    ///   - message: A human-readable failure message to send with the report.
    func reportFailure(testCase: XCTestCase, message: String) {
        guard let reportingService = reportingService else { return }
        
        queue.async {
            do {
                try reportingService.reportErrorWithScreenshot(message: message, testCase: testCase)
            } catch {
                print("🚨 RPListener Failure Reporting Error: \(error.localizedDescription)")
            }
        }
    }
  
    public /// Called when an individual test case finishes; enqueues a request to the reporting service to finish the test.
    /// - Note: If no reporting service is configured this is a no-op. The finish request is performed asynchronously on the listener queue.
    /// - Parameter testCase: The finished XCTestCase instance.
    func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let reportingService = reportingService else { return }

        queue.async {
            try? reportingService.finishTest(testCase)
        }
    }
  
    public /// Handles the end of a test suite by finishing the corresponding suite in the reporting service.
    /// 
    /// If no reporting service is available this is a no-op. Suites named containing "All tests" or
    /// "Selected tests" are ignored. The actual finish call is dispatched asynchronously on the
    /// listener's reporting queue: suites whose name contains ".xctest" trigger `finishRootSuite()`,
    /// otherwise `finishTestSuite()` is called. Any errors from the reporting service are suppressed.
    func testSuiteDidFinish(_ testSuite: XCTestSuite) {
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
  
    public /// Called when the test bundle finishes execution; if a reporting service is active, synchronously finishes the ReportPortal launch.
    /// - Parameter testBundle: The test bundle that has completed running; used only to follow XCTestObservation signature.
    func testBundleDidFinish(_ testBundle: Bundle) {
        guard let reportingService = reportingService else { return }

        queue.sync {
            try? reportingService.finishLaunch()
        }
    }

    // MARK: - Gherkin Detection & Name Extraction
    private /// Extracts Gherkin feature and scenario names for a given XCTestCase when the test originates from a Gherkin-backed runner.
    /// 
    /// Checks for compatibility with two Gherkin integrations (legacy `NativeTestCase` and `XCGNativeInitializer`) and, when present, returns the feature and scenario names mapped to the test case. If the test case is not from a supported Gherkin-backed class or the names cannot be resolved, returns `(nil, nil)`.
    /// - Parameters:
    ///   - testCase: The test case to inspect. Used to detect Gherkin-backed test types and derive feature/scenario names.
    /// - Returns: A tuple `(feature: String?, scenario: String?)` containing the resolved feature and scenario names, or `(nil, nil)` if not available.
    func extractGherkinNames(from testCase: XCTestCase) -> (feature: String?, scenario: String?) {
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
                let tupleAny = unmanagedResult.takeUnRetainedValue()
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

    private /// Extracts a human-readable scenario name from an XCTest raw test name.
    /// 
    /// The function attempts to parse the last space-separated component of `rawName` (commonly the Objective-C-style method token such as `-[_Class test_example_case]`), strips any trailing `]` characters, removes a leading `"test"` prefix if present, replaces underscores with spaces, and trims surrounding whitespace and newlines. If the method part cannot be determined, the original `rawName` is returned unchanged.
    /// - Parameter rawName: The raw test case name string produced by XCTest.
    /// - Returns: A cleaned, human-readable scenario name.
    func parseScenarioName(from rawName: String) -> String {
        guard let methodPart = rawName.split(separator: " ").last else { return rawName }
        var cleaned = methodPart.replacingOccurrences(of: "]", with: "")
        if cleaned.hasPrefix("test") {
            cleaned.removeFirst("test".count)
        }
        cleaned = cleaned.replacingOccurrences(of: "_", with: " ")
        return cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
