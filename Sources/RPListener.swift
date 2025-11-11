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
            print("Set 'YES' for 'PushTestDataToReportPortal' property in Info.plist if you want to put data to report portal")
            return
        }
        
        // Create service for v4.0.0 async/await parallel execution
        let reportingService = ReportingService(configuration: configuration)
        self.reportingService = reportingService
        
        // T013: Create launch for this test bundle using custom UUID (no API call needed)
        // This simplifies synchronization - no waiting for API response
        Task.detached(priority: .high) {
            // Generate custom UUID for launch (no API call, immediate availability)
            let customLaunchUUID = UUID().uuidString
            Logger.shared.info("📦 Generated custom launch UUID: \(customLaunchUUID)")
            
            // Create dummy task that returns the UUID immediately
            let launchTask = Task<String, Error> {
                return customLaunchUUID
            }
            
            // Store launch ID in LaunchManager immediately
            do {
                let launchID = try await LaunchManager.shared.createLaunch(launchTask: launchTask)
                Logger.shared.info("✅ Launch ready with custom UUID: \(launchID)")
                
                // Now start the actual launch in ReportPortal asynchronously (fire and forget)
                Task {
                    do {
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

                        // Create launch via ReportPortal API with custom UUID
                        let reportedLaunchID = try await reportingService.startLaunch(
                            name: enhancedLaunchName,
                            tags: configuration.tags,
                            attributes: attributes,
                            uuid: customLaunchUUID
                        )
                        Logger.shared.info("📡 Launch created in ReportPortal: \(reportedLaunchID)")
                    } catch {
                        Logger.shared.error("Failed to create launch in ReportPortal: \(error.localizedDescription)")
                    }
                }
            } catch {
                Logger.shared.error("Failed to store launch UUID: \(error.localizedDescription)")
            }
        }
    }
    
    /// Wait for launch ID to become available
    /// With custom UUID approach, launch ID is available immediately
    /// - Returns: Launch ID (custom UUID)
    /// - Throws: LaunchManagerError.launchNotStarted if launch not initiated (shouldn't happen)
    private func waitForLaunchID() async throws -> String {
        // With custom UUID, this returns immediately (no timeout needed)
        return try await launchManager.waitForLaunchID()
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
            // Wait for launch ID (properly awaits task, no polling)
            let launchID: String
            do {
                launchID = try await waitForLaunchID()
            } catch {
                Logger.shared.error("""
                    ❌ SUITE REGISTRATION FAILED: '\(testSuite.name)'
                    Reason: \(error.localizedDescription)
                    Impact: This suite will NOT be reported to ReportPortal
                    Action: Check launch creation logs and ReportPortal connectivity
                    """)
                return
            }
            
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

                // For test class suites, wait for parent root suite ID
                let parentSuiteID: String?
                if !isRootSuite {
                    // Wait for root suite ID to be created (synchronization point)
                    do {
                        Logger.shared.info("⏳ Waiting for root suite ID...", correlationID: correlationID)
                        parentSuiteID = try await waitForRootSuiteID()
                        Logger.shared.info("✅ Using root suite ID: \(parentSuiteID!)", correlationID: correlationID)
                    } catch {
                        Logger.shared.warning("""
                            ⚠️ Failed to get root suite ID for '\(testSuite.name)': \(error.localizedDescription)
                            Suite will be created at root level as fallback.
                            """, correlationID: correlationID)
                        parentSuiteID = nil
                    }
                } else {
                    parentSuiteID = nil
                    Logger.shared.info("📦 Creating ROOT SUITE...", correlationID: correlationID)
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
        guard let asyncService = reportingService else {
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test case '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T019: Register test case with OperationTracker for parallel execution
        Task {
            // Wait for launch ID (properly awaits task, no polling)
            let launchID: String
            do {
                launchID = try await waitForLaunchID()
            } catch {
                let testName = extractTestName(from: testCase)
                let className = String(describing: type(of: testCase))
                Logger.shared.error("""
                    ❌ TEST REGISTRATION FAILED: '\(className).\(testName)'
                    Reason: \(error.localizedDescription)
                    Impact: This test will NOT be reported to ReportPortal (but will still execute locally)
                    Action: Check launch creation logs and ReportPortal connectivity
                    """)
                return
            }
            
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
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test issue for '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T022: Async attachment upload for concurrent execution
        Task {
            // Wait for launch ID (don't drop early failures)
            let launchID: String
            do {
                launchID = try await waitForLaunchID()
            } catch {
                let testName = extractTestName(from: testCase)
                let className = String(describing: type(of: testCase))
                Logger.shared.warning("""
                    ⚠️ Cannot report test issue to ReportPortal: '\(className).\(testName)'
                    Reason: Launch ID not available - \(error.localizedDescription)
                    Impact: Test failure will not be visible in ReportPortal
                    """)
                return
            }

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
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test failure for '\(testCase.name)' will not be reported to ReportPortal.")
            return
        }
        
        // T022: Async attachment upload for concurrent execution
        Task {
            // Wait for launch ID (don't drop early failures)
            let launchID: String
            do {
                launchID = try await waitForLaunchID()
            } catch {
                let testName = extractTestName(from: testCase)
                let className = String(describing: type(of: testCase))
                Logger.shared.warning("""
                    ⚠️ Cannot report test failure to ReportPortal: '\(className).\(testName)'
                    Reason: Launch ID not available - \(error.localizedDescription)
                    Impact: Test failure will not be visible in ReportPortal
                    """)
                return
            }

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
                // Note: Screenshots are uploaded directly in failure methods, not here
                try await asyncService.finishTest(operation: operation)

                // Update aggregated launch status
                if let status = operation.status {
                    await launchManager.updateStatus(status)
                }

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
            print("🚨 RPListener Configuration Error: Reporting is disabled (PushTestDataToReportPortal=false). Test bundle completion will not be reported to ReportPortal.")
            return
        }
        
        // Read configuration to check if we should finalize
        let configuration = readConfiguration(from: testBundle)
        
        Task {
            Logger.shared.info("📦 Bundle finished. shouldFinishLaunch=\(configuration.shouldFinishLaunch)")
            
            // Check if this bundle should finalize the launch
            guard configuration.shouldFinishLaunch else {
                Logger.shared.info("⏭️ Skipping launch finalization (shouldFinishLaunch=false)")
                return
            }
            
            let isFinalized = await launchManager.isLaunchFinalized()
            Logger.shared.info("🔍 Launch finalized status: \(isFinalized)")

            if !isFinalized {
                // Finalize the launch
                guard let launchID = await launchManager.getLaunchID() else {
                    Logger.shared.error("❌ Cannot finalize launch: launch ID not found")
                    return
                }

                let status = await launchManager.getAggregatedStatus()
                Logger.shared.info("📊 Finalizing launch \(launchID) with status: \(status.rawValue)")

                do {
                    if let asyncService = reportingService {
                        try await asyncService.finalizeLaunch(launchID: launchID, status: status)
                        await launchManager.markFinalized()
                        Logger.shared.info("✅ Launch finalized successfully: \(launchID) with status: \(status.rawValue)")
                    }
                } catch {
                    Logger.shared.error("❌ Failed to finalize launch: \(error.localizedDescription)")
                }
            } else {
                Logger.shared.info("ℹ️ Bundle finished, launch already finalized")
            }
        }
    }
}
