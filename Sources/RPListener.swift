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

    // Root suite ID stored directly (no coordination needed for single bundle)
    private var rootSuiteID: String?
    
    // Task for root suite creation (to synchronize child suites)
    private var rootSuiteCreationTask: Task<String, Error>?
    
    // Flag to ensure launch is created only once
    private var isLaunchCreated = false
    
    public override init() {
        super.init()
        
        // XCTestObservationCenter requires main thread for observer registration
        // init() is typically called on main thread, but ensure it with precondition
        dispatchPrecondition(condition: .onQueue(.main))
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
            let launchName = bundleProperties["ReportPortalLaunchName"] as? String else
        {
            fatalError("Configure properties for report portal in the Info.plist")
        }
        
        let shouldReport: Bool
        if let pushTestDataString = bundleProperties["PushTestDataToReportPortal"] as? String {
            let normalized = pushTestDataString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            shouldReport = ["true", "yes", "1"].contains(normalized)
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
            launchMode: launchMode,
            testNameRules: testNameRules
        )
    }
    
    public func testBundleWillStart(_ testBundle: Bundle) {
        let configuration = readConfiguration(from: testBundle)
        
        guard configuration.shouldSendReport else {
            Logger.shared.warning("⚠️ Reporting disabled: Set 'YES' for 'PushTestDataToReportPortal' in Info.plist to enable ReportPortal reporting")
            return
        }
        
        // Prevent duplicate launch creation (in case testBundleWillStart called multiple times)
        guard !isLaunchCreated else {
            Logger.shared.info("⏭️ Bundle started but launch already created - skipping")
            return
        }
        
        isLaunchCreated = true
        Logger.shared.info("🎬 First bundle start detected - initializing ReportPortal reporting")
        
        // Create service for v4.0.0 async/await parallel execution
        let reportingService = ReportingService(configuration: configuration)
        self.reportingService = reportingService
        
        // Get launch UUID (synchronous access, no API call)
        // CI/CD Mode: All workers get same UUID from RP_LAUNCH_UUID env var
        // Local Mode: Each worker generates unique UUID
        let launchUUID = LaunchManager.shared.launchID
        Logger.shared.info("📦 Launch UUID resolved (no API call): \(launchUUID)")
        
        // Ensure launch is created via V2 API before any suites/tests are reported
        // This guarantees proper synchronization in parallel execution
        Task {
            await LaunchManager.shared.ensureLaunchStarted {
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

                // Create launch via V2 API with predefined UUID
                // 409 Conflict is handled gracefully by LaunchManager (means launch exists = success)
                let reportedLaunchID = try await reportingService.startLaunch(
                    name: enhancedLaunchName,
                    tags: configuration.tags,
                    attributes: attributes,
                    uuid: launchUUID
                )
                Logger.shared.info("📡 Launch created via V2 API: \(reportedLaunchID)")
            }
        }
    }
    
    private func buildEnhancedLaunchName(baseLaunchName: String, testPlanName: String?) -> String {
        if let testPlan = testPlanName, !testPlan.isEmpty {
            let sanitizedTestPlan = testPlan.replacingOccurrences(of: " ", with: "_")
            return "\(baseLaunchName): \(sanitizedTestPlan)"
        }
        return baseLaunchName
    }
    
    /// Wait for root suite ID to become available
    /// Awaits the root suite creation task to avoid race conditions
    /// - Returns: Root suite ID if available
    /// - Throws: Error if root suite creation fails or hasn't been initiated
    private func waitForRootSuiteID() async throws -> String {
        // Fast path: root suite already created
        if let id = rootSuiteID {
            return id
        }
        
        // If no task exists, root suite hasn't been initiated yet
        guard let task = rootSuiteCreationTask else {
            throw NSError(
                domain: "RPListener",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Root suite creation has not been initiated yet"]
            )
        }
        
        // Wait for task to complete (no timeout needed - suite creation is fast)
        return try await task.value
    }
    
    public func testSuiteWillStart(_ testSuite: XCTestSuite) {
        Logger.shared.info("📋 testSuiteWillStart called: '\(testSuite.name)'")
        
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test suite '\(testSuite.name)' will not be reported to ReportPortal")
            return
        }
        
        guard
            !testSuite.name.contains("All tests"),
            !testSuite.name.contains("Selected tests") else
        {
            Logger.shared.info("⏭️ Skipping meta-suite: '\(testSuite.name)'")
            return
        }
        
        Logger.shared.info("🔄 Processing suite: '\(testSuite.name)' (starting async Task)")
        
        // Register suite with OperationTracker for parallel execution
        Task {
            // CRITICAL: Wait for launch to be ready before creating any suites
            // This ensures V2 API launch exists before we start reporting hierarchy
            // Using waitUntilReady() since launch creation happens in testBundleWillStart
            await LaunchManager.shared.waitUntilReady()
            
            // Verify launch is actually ready
            let isReady = await LaunchManager.shared.isReady()
            guard isReady else {
                Logger.shared.warning("⚠️  Launch not ready, skipping suite creation for: \(testSuite.name)")
                return
            }
            
            // Get launch ID (synchronous access after launch is ready)
            let launchID = launchManager.launchID
            
            do {
                let correlationID = UUID()
                let isRootSuite = testSuite.name.contains(".xctest")

                // Build consistent identifier: use suite name as-is
                // For test class suites, XCTest provides the class name
                // For root suites, it's the bundle name with .xctest extension
                let identifier = testSuite.name

                // DIAGNOSTIC: Log suite details to understand naming
                Logger.shared.info("""
                    📦 SUITE STARTING:
                    - testSuite.name: '\(testSuite.name)'
                    - identifier: '\(identifier)'
                    - isRoot: \(isRootSuite)
                    - testCount: \(testSuite.testCaseCount)
                    """, correlationID: correlationID)

                // SIMPLIFIED HIERARCHY: All test class suites at root level
                // Root .xctest bundle suite is often skipped by test plans/CLI execution
                // Creating flat structure: Launch → Test Class Suites → Tests
                let parentSuiteID: String? = nil

                if isRootSuite {
                    Logger.shared.info("📦 ROOT BUNDLE SUITE DETECTED: \(testSuite.name) (will be skipped - using flat hierarchy)", correlationID: correlationID)
                    // Don't create the root bundle suite - it's redundant
                    return
                } else {
                    Logger.shared.info("📦 Creating TEST CLASS SUITE at root level", correlationID: correlationID)
                }

                // Create suite operation
                var operation = SuiteOperation(
                    correlationID: correlationID,
                    suiteID: "", // Will be set after API call
                    rootSuiteID: parentSuiteID,
                    suiteName: testSuite.name,
                    status: nil,
                    startTime: Date(),
                    childTestIDs: [],
                    metadata: [:]
                )

                // Register suite in tracker with consistent identifier
                await operationTracker.registerSuite(operation, identifier: identifier)

                Logger.shared.info("✅ Suite registered: '\(identifier)' → ID: pending", correlationID: correlationID)

                // Create task for suite creation
                let suiteCreationTask = Task<String, Error> {
                    // Start suite in ReportPortal
                    let apiStartTime = Date()
                    Logger.shared.info("📡 Calling ReportPortal API to create suite...", correlationID: correlationID)
                    let suiteID = try await asyncService.startSuite(operation: operation, launchID: launchID)
                    let apiDuration = Date().timeIntervalSince(apiStartTime)
                    Logger.shared.info("📡 API call completed in \(Int(apiDuration * 1000))ms", correlationID: correlationID)
                    return suiteID
                }
                
                // Store task for root suite (so child suites can await it)
                if isRootSuite {
                    self.rootSuiteCreationTask = suiteCreationTask
                    Logger.shared.info("📌 Root suite creation task stored", correlationID: correlationID)
                }
                
                // Execute the task and get suite ID
                let suiteID = try await suiteCreationTask.value

                // Update operation with suite ID
                operation.suiteID = suiteID
                await operationTracker.updateSuite(operation, identifier: identifier)

                // Store root suite ID if this is root
                if isRootSuite {
                    self.rootSuiteID = suiteID
                    Logger.shared.info("🎯 Root suite ID stored: \(suiteID)", correlationID: correlationID)
                }

                Logger.shared.info("✅ Suite started: \(suiteID)", correlationID: correlationID)
            } catch {
                Logger.shared.error("Failed to start suite '\(testSuite.name)': \(error.localizedDescription)")
            }
        }
    }
    
    
    public func testCaseWillStart(_ testCase: XCTestCase) {
        Logger.shared.info("🧪 testCaseWillStart called: '\(testCase.name)'")
        
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test case '\(testCase.name)' will not be reported to ReportPortal")
            return
        }
        
        Logger.shared.info("🔄 Processing test case: '\(testCase.name)' (starting async Task)")
        
        // Register test case with OperationTracker for parallel execution
        Task {
            // CRITICAL: Wait for launch to be ready before creating any tests
            // This ensures V2 API launch exists before we start reporting tests
            // Using waitUntilReady() since launch creation happens in testBundleWillStart
            await LaunchManager.shared.waitUntilReady()
            
            // Verify launch is actually ready
            let isReady = await LaunchManager.shared.isReady()
            guard isReady else {
                Logger.shared.warning("⚠️  Launch not ready, skipping test creation for: \(testCase.name)")
                return
            }
            
            // Get launch ID (synchronous access after launch is ready)
            let launchID = launchManager.launchID
            
            do {
                let correlationID = UUID()

                // Extract test information
                let testName = extractTestName(from: testCase)
                let className = String(describing: type(of: testCase))
                let identifier = "\(className).\(testName)"

                // DIAGNOSTIC: Log test details
                Logger.shared.info("""
                    🧪 TEST STARTING:
                    - testCase.name: '\(testCase.name)'
                    - testName: '\(testName)'
                    - className: '\(className)'
                    - Looking for suite: '\(className)'
                    """, correlationID: correlationID)

                // Get parent suite ID (from current suite context)
                guard let suiteID = await getCurrentSuiteID(for: className) else {
                    let activeSuites = await operationTracker.getAllSuiteIdentifiers()
                    Logger.shared.error("""
                        ❌ TEST REGISTRATION FAILED: '\(className).\(testName)'
                        Reason: Parent suite ID not found for class '\(className)'
                        Active suites: \(activeSuites.joined(separator: ", "))
                        Impact: Cannot establish test hierarchy in ReportPortal
                        Hint: Suite may have failed to start or identifier mismatch
                        """)
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
                    status: nil,
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
    // XCTest suite names should match the class name for test class suites
    // Uses event-driven waiting (continuations) to handle async suite registration
    private func getCurrentSuiteID(for className: String) async -> String? {
        // Try waiting for suite to be registered (handles async registration race)
        // This uses continuations - test will pause until suite registers or timeout occurs
        do {
            let suiteOp = try await operationTracker.waitForSuite(identifier: className, timeout: 10)
            Logger.shared.debug("Found suite for class '\(className)' via event-driven wait")
            return suiteOp.suiteID
        } catch {
            Logger.shared.warning("Suite '\(className)' not registered after waiting: \(error.localizedDescription)")
        }

        // If exact match failed after waiting, check all registered suites for potential matches
        // This handles edge cases where XCTest might provide different naming
        let allSuites = await operationTracker.getAllSuiteIdentifiers()
        Logger.shared.debug("Searching for suite matching class '\(className)' in: [\(allSuites.joined(separator: ", "))]")

        // Try to find a suite that contains the class name
        for suiteIdentifier in allSuites {
            if suiteIdentifier.contains(className) || className.contains(suiteIdentifier) {
                if let suiteOp = await operationTracker.getSuite(identifier: suiteIdentifier) {
                    Logger.shared.info("Found suite '\(suiteIdentifier)' for class '\(className)' via partial match")
                    return suiteOp.suiteID
                }
            }
        }

        // Last resort: use root suite ID if available
        // This happens when test class suite failed to start but root suite exists
        if let rootID = self.rootSuiteID {
            Logger.shared.error("""
                ❌ SUITE LOOKUP FAILED - USING FALLBACK:
                - Searching for: '\(className)'
                - Registered suites: [\(allSuites.joined(separator: ", "))]
                - Using root suite as fallback
                - Impact: Test will appear at root level instead of under class suite
                - Likely cause: testSuite.name != className (identifier mismatch)
                - Action: Check logs above to see suite registration names vs test class names
                """)
            return rootID
        }

        Logger.shared.error("""
            ❌ CRITICAL: No suite found for class '\(className)' and no root suite available.
            Tests cannot be reported to ReportPortal.
            """)
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
            Logger.shared.warning("⚠️ Reporting disabled: Test issue for '\(testCase.name)' will not be reported to ReportPortal")
            return
        }
        
        // Async attachment upload for concurrent execution
        Task {
            // Get launch ID (lazy initialization on first access)
            let launchID = launchManager.launchID

            // Build identifier to get test operation
            let testName = extractTestName(from: testCase)
            let className = String(describing: type(of: testCase))
            let identifier = "\(className).\(testName)"

            guard let operation = await operationTracker.getTest(identifier: identifier) else {
                Logger.shared.warning("""
                    ⚠️ Cannot report test issue: Test operation not found for '\(identifier)'
                    Reason: Test may not have been registered successfully
                    Impact: Test failure details will not be visible in ReportPortal
                    """)
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

                // Capture and upload screenshot directly (v3.x approach)
                #if canImport(UIKit)
                do {
                    let screenshot = await XCUIScreen.main.screenshot()
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    let filename = "failure_screenshot_\(timestamp).png"

                    try await asyncService.postScreenshot(
                        screenshotData: await screenshot.pngRepresentation,
                        filename: filename,
                        itemID: operation.testID,
                        launchID: launchID,
                        correlationID: operation.correlationID
                    )
                    Logger.shared.info("📸 Screenshot uploaded successfully", correlationID: operation.correlationID)
                } catch {
                    Logger.shared.warning("Failed to upload screenshot: \(error.localizedDescription)", correlationID: operation.correlationID)
                }
                #endif

                Logger.shared.info("TEST FAIL reported", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to report TEST FAIL: \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    // For iOs 17+
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test failure for '\(testCase.name)' will not be reported to ReportPortal")
            return
        }
        
        // Async attachment upload for concurrent execution
        Task {
            // Get launch ID (lazy initialization on first access)
            let launchID = launchManager.launchID

            // Build identifier to get test operation
            let testName = extractTestName(from: testCase)
            let className = String(describing: type(of: testCase))
            let identifier = "\(className).\(testName)"

            guard let operation = await operationTracker.getTest(identifier: identifier) else {
                Logger.shared.warning("""
                    ⚠️ Cannot report test failure: Test operation not found for '\(identifier)'
                    Reason: Test may not have been registered successfully
                    Impact: Test failure details will not be visible in ReportPortal
                    """)
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

                // Capture and upload screenshot directly (v3.x approach, works on iOS 17+)
                #if canImport(UIKit)
                do {
                    let screenshot = await XCUIScreen.main.screenshot()
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    let filename = "failure_screenshot_\(timestamp).png"

                    try await asyncService.postScreenshot(
                        screenshotData: await screenshot.pngRepresentation,
                        filename: filename,
                        itemID: operation.testID,
                        launchID: launchID,
                        correlationID: operation.correlationID
                    )
                    Logger.shared.info("📸 Screenshot uploaded successfully", correlationID: operation.correlationID)
                } catch {
                    Logger.shared.warning("Failed to upload screenshot: \(error.localizedDescription)", correlationID: operation.correlationID)
                }
                #endif

                Logger.shared.info("Failure reported", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to report failure: \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test completion for '\(testCase.name)' will not be reported to ReportPortal")
            return
        }
        
        // Finalize test with status update and cleanup
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
                // Note: Screenshots are uploaded directly in failure methods, not here
                try await asyncService.finishTest(operation: operation)

                // Unregister test from tracker (cleanup)
                await operationTracker.unregisterTest(identifier: identifier)

                let statusString = operation.status?.rawValue ?? "UNKNOWN"
                Logger.shared.info("Test finished: \(operation.testID) with status: \(statusString)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to finish test '\(testCase.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test suite completion for '\(testSuite.name)' will not be reported to ReportPortal")
            return
        }
        
        guard
            !testSuite.name.contains("All tests"),
            !testSuite.name.contains("Selected tests") else
        {
            return
        }
        
        // Finalize suite with OperationTracker
        Task {
            let identifier = testSuite.name
            Logger.shared.info("🏁 testSuiteDidFinish called - Suite: '\(identifier)'")
            
            // Retrieve suite operation from tracker
            guard let operation = await operationTracker.getSuite(identifier: identifier) else {
                Logger.shared.error("❌ Suite operation not found in tracker: \(identifier)")
                return
            }
            
            do {
                // Determine final status (would be updated from child tests in production)
                // For now, keep as-is - in full implementation, aggregate from child tests
                
                Logger.shared.info("📡 Finishing suite '\(identifier)' in ReportPortal...", correlationID: operation.correlationID)
                
                // Finish suite in ReportPortal
                try await asyncService.finishSuite(operation: operation)
                
                // Unregister suite from tracker (cleanup)
                await operationTracker.unregisterSuite(identifier: identifier)
                
                Logger.shared.info("✅ Suite finished: \(operation.suiteID)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("❌ Failed to finish suite '\(testSuite.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testBundleDidFinish(_ testBundle: Bundle) {
        Logger.shared.info("🏁 testBundleDidFinish called - Bundle: \(testBundle.bundleIdentifier ?? "unknown")")
        
        guard reportingService != nil else {
            Logger.shared.warning("⚠️ Reporting disabled: Test bundle completion will not be reported to ReportPortal")
            return
        }
        
        Logger.shared.info("📦 Bundle finished - finalizing launch")
        
        // CRITICAL: Use semaphore to block until finalization completes
        // XCTest process will terminate immediately after testBundleDidFinish returns,
        // so we MUST block here to ensure async finalization completes
        let semaphore = DispatchSemaphore(value: 0)
        
        Task {
            // CRITICAL: Wait for pending async operations (screenshots, logs, test/suite reporting) to complete
            // Test failures and runtime issues trigger async Tasks that may still be executing
            // when bundle finishes. In script/CI mode, these tasks need extra time to complete
            // their network calls to ReportPortal before process termination.
            Logger.shared.info("⏸️  Starting 15-second grace period for pending async operations...")
            Logger.shared.info("   This ensures all test/suite start/finish calls complete before process exit")
            try? await Task.sleep(nanoseconds: 15_000_000_000) // 15 second grace period
            Logger.shared.info("⏰ Grace period completed - proceeding with launch finalization")
            
            let launchID = launchManager.launchID

            // ReportPortal will calculate the final status from all test results
            Logger.shared.info("📊 Finalizing launch \(launchID)")

            do {
                if let asyncService = reportingService {
                    try await asyncService.finalizeLaunch(launchID: launchID, status: .passed)
                    Logger.shared.info("✅ Launch finalized successfully: \(launchID)")
                }
            } catch {
                Logger.shared.error("❌ Failed to finalize launch: \(error.localizedDescription)")
            }
            
            // CRITICAL FIX: Remove test observer on main thread (XCTestObservationCenter requirement)
            // This must happen on main thread to prevent "Test observers can only be registered 
            // and unregistered on the main thread" assertion
            await MainActor.run {
                XCTestObservationCenter.shared.removeTestObserver(self)
                Logger.shared.info("🛑 Test observer removed - execution complete")
            }
            
            // Signal that finalization is complete
            semaphore.signal()
        }
        
        // CRITICAL: Block until finalization completes (prevents process termination)
        // Timeout after 20 seconds (15s grace + 5s for API call)
        let timeout = DispatchTime.now() + .seconds(20)
        let result = semaphore.wait(timeout: timeout)
        
        if result == .timedOut {
            Logger.shared.error("⚠️ Launch finalization timed out after 20 seconds")
        } else {
            Logger.shared.info("✅ Launch finalization completed successfully")
        }
    }
}
