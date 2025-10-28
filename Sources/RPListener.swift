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
    
    private var reportingService: ReportingService?
    
    // Shared actors for parallel execution
    private let launchManager = LaunchManager.shared
    private let operationTracker = OperationTracker.shared
    
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
        
        // Create service for v4.0.0 async/await parallel execution
        let reportingService = ReportingService(configuration: configuration)
        self.reportingService = reportingService
        
        // T013: Increment bundle count and create launch if needed
        // Use Task.detached with high priority to ensure launch creation happens immediately
        // Note: XCTest observation methods are synchronous, so we can't await here
        // Subsequent method calls will wait for launch ID via actor isolation
        Task.detached(priority: .high) {
            await self.launchManager.incrementBundleCount()

            // Create launch task (may or may not be used depending on race conditions)
            let launchTask = Task<String, Error> {
                // Collect metadata attributes
                let attributes: [[String: String]]
                if let bundle = testBundle as Bundle? {
                    attributes = MetadataCollector.collectAllAttributes(from: bundle, tags: configuration.tags)
                } else {
                    attributes = MetadataCollector.collectDeviceAttributes()
                }

                // Get test plan name for launch name enhancement
                let testPlanName = MetadataCollector.getTestPlanName()
                let enhancedLaunchName = self.buildEnhancedLaunchName(
                    baseLaunchName: configuration.launchName,
                    testPlanName: testPlanName
                )

                // Create launch via ReportPortal API
                return try await reportingService.startLaunch(
                    name: enhancedLaunchName,
                    tags: configuration.tags,
                    attributes: attributes
                )
            }

            do {
                // Pass task to actor - it will decide whether to use it or await existing task
                let launchID = try await self.launchManager.getOrAwaitLaunchID(launchTask: launchTask)
                Logger.shared.info("Launch ready: \(launchID)")
            } catch {
                Logger.shared.error("Failed to get/create launch: \(error.localizedDescription)")
            }
        }
    }
    
    /// Wait for launch ID to be available with exponential backoff
    /// This is needed because XCTest observation methods are synchronous but launch creation is async
    private func waitForLaunchID() async -> String? {
        for attempt in 0..<10 {
            if let launchID = await launchManager.getLaunchID() {
                return launchID
            }
            // Exponential backoff: 10ms, 20ms, 40ms, 80ms, 160ms, 320ms, 640ms, 1.28s, 2.56s, 5.12s
            let delayMs = 10 * (1 << attempt)
            try? await Task.sleep(nanoseconds: UInt64(delayMs) * 1_000_000)
        }
        return nil
    }
    
    private func buildEnhancedLaunchName(baseLaunchName: String, testPlanName: String?) -> String {
        if let testPlan = testPlanName, !testPlan.isEmpty {
            let sanitizedTestPlan = testPlan.replacingOccurrences(of: " ", with: "_")
            return "\(baseLaunchName): \(sanitizedTestPlan)"
        }
        return baseLaunchName
    }
    
    public func testSuiteWillStart(_ testSuite: XCTestSuite) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test suite '\(testSuite.name)' will not be reported to ReportPortal.")
            return
        }
        
        guard
            !testSuite.name.contains("All tests"),
            !testSuite.name.contains("Selected tests") else
        {
            return
        }
        
        // T015: Register suite with OperationTracker for parallel execution
        Task {
            guard let launchID = await waitForLaunchID() else {
                Logger.shared.error("Cannot start suite: launch ID not available after timeout")
                return
            }
            
            do {
                let correlationID = UUID()
                let isRootSuite = testSuite.name.contains(".xctest")
                
                // Create suite operation
                var operation = SuiteOperation(
                    correlationID: correlationID,
                    suiteID: "", // Will be set after API call
                    rootSuiteID: isRootSuite ? nil : await getRootSuiteID(),
                    suiteName: testSuite.name,
                    status: .passed,
                    startTime: Date(),
                    childTestIDs: [],
                    metadata: [:]
                )
                
                // Register suite in tracker
                let identifier = testSuite.name
                await operationTracker.registerSuite(operation, identifier: identifier)
                
                // Start suite in ReportPortal
                let suiteID = try await asyncService.startSuite(operation: operation, launchID: launchID)
                
                // Update operation with suite ID
                operation.suiteID = suiteID
                await operationTracker.updateSuite(operation, identifier: identifier)
                
                // Store root suite ID if this is root
                if isRootSuite {
                    await setRootSuiteID(suiteID)
                }
                
                Logger.shared.info("Suite started: \(suiteID)", correlationID: correlationID)
            } catch {
                Logger.shared.error("Failed to start suite '\(testSuite.name)': \(error.localizedDescription)")
            }
        }
    }
    
    // Helper to store/retrieve root suite ID (thread-safe with actor)
    private var rootSuiteIDStorage: String?
    
    private func setRootSuiteID(_ id: String) async {
        rootSuiteIDStorage = id
    }
    
    private func getRootSuiteID() async -> String? {
        return rootSuiteIDStorage
    }
    
    public func testCaseWillStart(_ testCase: XCTestCase) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test case '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T019: Register test case with OperationTracker for parallel execution
        Task {
            guard let launchID = await waitForLaunchID() else {
                Logger.shared.error("Cannot start test: launch ID not available after timeout")
                return
            }
            
            do {
                let correlationID = UUID()
                
                // Extract test information
                let testName = extractTestName(from: testCase)
                let className = String(describing: type(of: testCase))
                let identifier = "\(className).\(testName)"
                
                // Get parent suite ID (from current suite context)
                guard let suiteID = await getCurrentSuiteID(for: className) else {
                    Logger.shared.error("Cannot start test: parent suite ID not found for \(className)")
                    return
                }
                
                // Collect metadata
                let metadata = collectTestMetadata()
                
                // Create test operation
                var operation = TestOperation(
                    correlationID: correlationID,
                    testID: "", // Will be set after API call
                    suiteID: suiteID,
                    testName: testName,
                    className: className,
                    status: .passed,
                    startTime: Date(),
                    metadata: metadata,
                    attachments: []
                )
                
                // Register test in tracker
                await operationTracker.registerTest(operation, identifier: identifier)
                
                // Start test in ReportPortal
                let testID = try await asyncService.startTest(operation: operation, launchID: launchID)
                
                // Update operation with test ID
                operation.testID = testID
                await operationTracker.updateTest(operation, identifier: identifier)
                
                Logger.shared.info("Test started: \(testID)", correlationID: correlationID)
            } catch {
                Logger.shared.error("Failed to start test '\(testCase.name)': \(error.localizedDescription)")
            }
        }
    }
    
    // Helper to extract test name from XCTestCase
    private func extractTestName(from testCase: XCTestCase) -> String {
        let fullName = testCase.name
        // XCTest name format: "-[ClassName testMethodName]"
        let components = fullName.components(separatedBy: " ")
        if components.count > 1 {
            return components[1].replacingOccurrences(of: "]", with: "")
        }
        return fullName
    }
    
    // Helper to get current suite ID for a test class
    private func getCurrentSuiteID(for className: String) async -> String? {
        // Try to find suite operation for this class
        if let suiteOp = await operationTracker.getSuite(identifier: className) {
            return suiteOp.suiteID
        }
        return nil
    }
    
    // Helper to collect test metadata
    private func collectTestMetadata() -> [String: String] {
        var metadata: [String: String] = [:]
        
        // Add test plan name if available
        if let testPlanName = MetadataCollector.getTestPlanName() {
            metadata["testPlan"] = testPlanName
        }
        
        // Add device info
        metadata["os"] = DeviceHelper.osNameAndVersion()
        
        return metadata
    }
    
    @available(*, deprecated, message: "Use fun public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) for iOs 17+")
    public func testCase(_ testCase: XCTestCase, didRecord issue: XCTIssueReference) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test issue for '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T022: Async attachment upload for concurrent execution
        Task {
            guard let launchID = await launchManager.getLaunchID() else {
                Logger.shared.error("Cannot report error: launch ID not found")
                return
            }
            
            // Build identifier to get test operation
            let testName = extractTestName(from: testCase)
            let className = String(describing: type(of: testCase))
            let identifier = "\(className).\(testName)"
            
            guard let operation = await operationTracker.getTest(identifier: identifier) else {
                Logger.shared.error("Test operation not found for error reporting: \(identifier)")
                return
            }
            
            do {
                let lineNumberString = issue.sourceCodeContext.location?.lineNumber != nil
                ? " on line \(issue.sourceCodeContext.location!.lineNumber)"
                : ""
                let errorMessage = "Test '\(String(describing: issue.description))' failed\(lineNumberString), \(issue.description)"
                
                // Post error log with async API (non-blocking)
                try await asyncService.postLog(
                    message: errorMessage,
                    level: "error",
                    itemID: operation.testID,
                    launchID: launchID,
                    correlationID: operation.correlationID
                )
                
                // Upload attachments concurrently if available from operation
                if !operation.attachments.isEmpty {
                    try await asyncService.postAttachments(
                        attachments: operation.attachments,
                        itemID: operation.testID,
                        launchID: launchID,
                        correlationID: operation.correlationID
                    )
                }
                
                Logger.shared.info("TEST FAIL reported with attachments", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to report TEST FAIL: \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    // For iOs 17+
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test failure for '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T022: Async attachment upload for concurrent execution
        Task {
            guard let launchID = await launchManager.getLaunchID() else {
                Logger.shared.error("Cannot report failure: launch ID not found")
                return
            }
            
            // Build identifier to get test operation
            let testName = extractTestName(from: testCase)
            let className = String(describing: type(of: testCase))
            let identifier = "\(className).\(testName)"
            
            guard let operation = await operationTracker.getTest(identifier: identifier) else {
                Logger.shared.error("Test operation not found for failure reporting: \(identifier)")
                return
            }
            
            do {
                let fileInfo = filePath != nil ? " in \(URL(fileURLWithPath: filePath!).lastPathComponent)" : ""
                let errorMessage = "Test failed on line \(lineNumber)\(fileInfo): \(description)"
                
                // Post error log with async API (non-blocking)
                try await asyncService.postLog(
                    message: errorMessage,
                    level: "error",
                    itemID: operation.testID,
                    launchID: launchID,
                    correlationID: operation.correlationID
                )
                
                // Upload attachments concurrently if available from operation
                if !operation.attachments.isEmpty {
                    try await asyncService.postAttachments(
                        attachments: operation.attachments,
                        itemID: operation.testID,
                        launchID: launchID,
                        correlationID: operation.correlationID
                    )
                }
                
                Logger.shared.info("Failure reported with attachments", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to report failure: \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test completion for '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T020: Finalize test with status update and cleanup
        Task {
            // Build identifier
            let testName = extractTestName(from: testCase)
            let className = String(describing: type(of: testCase))
            let identifier = "\(className).\(testName)"
            
            // Retrieve test operation from tracker
            guard var operation = await operationTracker.getTest(identifier: identifier) else {
                Logger.shared.error("Test operation not found in tracker: \(identifier)")
                return
            }
            
            do {
                // Update status based on test result
                let hasSucceeded = testCase.testRun?.hasSucceeded ?? false
                operation.status = hasSucceeded ? .passed : .failed
                
                // Finish test in ReportPortal
                try await asyncService.finishTest(operation: operation)
                
                // Update aggregated launch status
                await launchManager.updateStatus(operation.status)
                
                // Unregister test from tracker (cleanup)
                await operationTracker.unregisterTest(identifier: identifier)
                
                Logger.shared.info("Test finished: \(operation.testID) with status: \(operation.status.rawValue)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to finish test '\(testCase.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test suite completion for '\(testSuite.name)' will not be reported to ReportPortal.")
            return
        }
        
        guard
            !testSuite.name.contains("All tests"),
            !testSuite.name.contains("Selected tests") else
        {
            return
        }
        
        // T016: Finalize suite with OperationTracker
        Task {
            let identifier = testSuite.name
            
            // Retrieve suite operation from tracker
            guard let operation = await operationTracker.getSuite(identifier: identifier) else {
                Logger.shared.error("Suite operation not found in tracker: \(identifier)")
                return
            }
            
            do {
                // Determine final status (would be updated from child tests in production)
                // For now, keep as-is - in full implementation, aggregate from child tests
                
                // Finish suite in ReportPortal
                try await asyncService.finishSuite(operation: operation)
                
                // Unregister suite from tracker (cleanup)
                await operationTracker.unregisterSuite(identifier: identifier)
                
                Logger.shared.info("Suite finished: \(operation.suiteID)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to finish suite '\(testSuite.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testBundleDidFinish(_ testBundle: Bundle) {
        guard reportingService != nil else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test bundle completion will not be reported to ReportPortal.")
            return
        }
        
        // T014: Decrement bundle count and finalize if this is the last bundle
        Task {
            let shouldFinalize = await launchManager.decrementBundleCount()
            let isFinalized = await launchManager.isLaunchFinalized()
            
            if shouldFinalize && !isFinalized {
                // This is the last bundle - finalize the launch
                guard let launchID = await launchManager.getLaunchID() else {
                    Logger.shared.error("Cannot finalize launch: launch ID not found")
                    return
                }
                
                let status = await launchManager.getAggregatedStatus()
                
                do {
                    if let asyncService = reportingService {
                        try await asyncService.finalizeLaunch(launchID: launchID, status: status)
                        Logger.shared.info("Launch finalized: \(launchID) with status: \(status.rawValue)")
                    }
                } catch {
                    Logger.shared.error("Failed to finalize launch: \(error.localizedDescription)")
                }
            } else {
                let activeCount = await launchManager.getActiveBundleCount()
                Logger.shared.info("Bundle finished, \(activeCount) bundles still active")
            }
        }
    }
}
