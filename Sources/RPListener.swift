//  Copyright 2025 EPAM Systems
//  
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//  
//      https://www.apache.org/licenses/LICENSE-2.0
//  
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import XCTest

open class RPListener: NSObject, XCTestObservation {

    // Plain existential (no `any`): the `any` keyword is Swift 5.6+, and the package/podspec
    // declare Swift 5.5 as the minimum supported version.
    private var reportingService: ReportingServiceProtocol?

    /// Test seam: factory for the reporting service. Production uses the real
    /// `ReportingService`; unit tests inject a recording double to assert call ordering.
    var makeReportingService: (AgentConfiguration) -> ReportingServiceProtocol = {
        ReportingService(configuration: $0)
    }

    /// Test seam: when set, used instead of reading the bundle's `Info.plist`, so ordering
    /// tests don't need a configured test bundle. `nil` in production.
    private var injectedConfiguration: AgentConfiguration?

    // Shared actor for parallel execution
    private let operationTracker = OperationTracker.shared

    // Root suite ID stored directly (no coordination needed for single bundle)
    private var rootSuiteID: String?
    
    // Task for root suite creation (to synchronize child suites)
    private var rootSuiteCreationTask: Task<String, Error>?
    
    // Flag to ensure launch is created only once
    private var isLaunchCreated = false
    
    /// The launch gate: a single Task created SYNCHRONOUSLY in `testBundleWillStart`.
    /// All consumers (testSuiteWillStart, testCaseWillStart) await this Task before
    /// sending anything to ReportPortal. This eliminates the actor priority inversion
    /// bug: there's no race because everyone awaits the SAME Task instance.
    ///
    /// Its value is `true` when the launch was created (or already existed, 409) and
    /// `false` when launch creation failed after all retries. Consumers must skip
    /// reporting when it's `false` — otherwise they'd send suites/tests against a
    /// launch that does not exist, producing a cascade of failing child-item calls.
    ///
    /// Why this works: `Task<Bool, Never>` is Sendable. It's assigned on main thread
    /// (where XCTest callbacks run) BEFORE testSuiteWillStart can fire. Even if the
    /// actor picks a suite-Task first, that Task awaits `launchGate.value` which
    /// suspends until the gate's body completes — guaranteeing launch exists first.
    private var launchGate: Task<Bool, Never>?

    /// Reporting work per test class, chained in XCTest callback order. XCTest delivers the
    /// callbacks serially on the main thread, so a class's requests go out as start suite →
    /// start test → logs → finish test → finish suite: a test is never finished before it was
    /// started, and a suite never before its last test (ReportPortal would force-finish that
    /// test with the suite's status). Classes are chained separately, so one class's requests
    /// don't hold up the next class.
    private var classChains: [String: Task<Void, Never>] = [:]

    /// `ReportPortalCollapseRetries`: mark tests as retries so ReportPortal nests earlier
    /// attempts of a test under its last one.
    private var collapseRetries = false

    /// Device and OS on every test of a shared launch, so each attempt shows where it ran.
    private var testAttributes: [[String: String]] = []

    /// Upper bound on how long the end of the bundle waits for reporting still in flight.
    static let finalizationTimeout: TimeInterval = 120

    private func enqueue(on className: String, _ work: @escaping () async -> Void) {
        let previous = classChains[className]
        classChains[className] = Task {
            await previous?.value
            await work()
        }
    }

    public override init() {
        super.init()

        // XCTestObservationCenter requires main thread for observer registration
        // init() is typically called on main thread, but ensure it with precondition
        dispatchPrecondition(condition: .onQueue(.main))
        XCTestObservationCenter.shared.addTestObserver(self)
    }

    /// Test-only initializer: injects a configuration + a reporting-service factory and
    /// deliberately SKIPS `XCTestObservationCenter` registration, so a test can drive the
    /// observation callbacks directly without the listener also reacting to the test run
    /// itself. Never used in production (the public `init()` is the only registered path).
    init(injectedConfiguration: AgentConfiguration,
         makeReportingService: @escaping (AgentConfiguration) -> ReportingServiceProtocol) {
        self.injectedConfiguration = injectedConfiguration
        self.makeReportingService = makeReportingService
        super.init()
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
        let configuration = injectedConfiguration ?? readConfiguration(from: testBundle)
        
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
        let reportingService = makeReportingService(configuration)
        self.reportingService = reportingService
        
        // Get launch UUID — resolved once per process, stable across all calls.
        // The test bundle is passed so the Info.plist tier can be read: on real-device
        // farms it is the only channel that reaches every shard.
        let launchUUID = LaunchUUID.resolve(from: testBundle)
        Logger.shared.info("📦 Launch UUID: \(launchUUID)")

        collapseRetries = RPListener.resolveCollapseRetries(from: testBundle)
        if LaunchUUID.source != .generated {
            testAttributes = MetadataCollector.collectDeviceAttributes()
        }
        
        // Create the launch gate — a single Task that all subsequent XCTest callbacks
        // await before touching ReportPortal. Solves the "4 of 6" priority inversion:
        // XCTest callbacks are synchronous (void return), so we MUST use Task {}. But
        // by storing ONE gate Task and having all consumers `await gate.value`, we
        // guarantee ordering without locks or actor scheduling assumptions.
        // Capture only Sendable values — no `self` — so the gate Task does not retain
        // the observer (and so it compiles cleanly under strict concurrency checking).
        let gate = Task { [reportingService] () -> Bool in
            var attributes = MetadataCollector.collectAllAttributes(from: testBundle, tags: configuration.tags)

            if let group = RPListener.resolveMergeGroup(from: testBundle) {
                attributes.append(["key": "merge_group", "value": group])
            }

            let env = ProcessInfo.processInfo.environment
            if let runID = [env["RP_CI_RUN_ID"], env["GITHUB_RUN_ID"]]
                .compactMap({ $0?.trimmingCharacters(in: .whitespacesAndNewlines) })
                .first(where: { !$0.isEmpty }) {
                attributes.append(["key": "ci_run_id", "value": runID])
            }

            let testPlanName = MetadataCollector.getTestPlanName()
            let enhancedLaunchName = RPListener.buildEnhancedLaunchName(
                baseLaunchName: configuration.launchName,
                testPlanName: testPlanName
            )

            // Retry with backoff — transient network errors shouldn't kill the whole shard's reporting
            let maxAttempts = 3
            for attempt in 1...maxAttempts {
                do {
                    let id = try await reportingService.startLaunch(
                        name: enhancedLaunchName,
                        tags: configuration.tags,
                        attributes: attributes,
                        uuid: launchUUID
                    )
                    Logger.shared.info("✅ Launch created: \(id) (attempt \(attempt)/\(maxAttempts))")
                    if LaunchUUID.source != .generated {
                        await RPListener.alignClock(withSharedLaunch: launchUUID, using: reportingService)
                    }
                    return true
                } catch {
                    // 409 = a launch with this UUID already exists. Two cases:
                    //   1. CI/CD with a shared RP_LAUNCH_UUID — another worker created it (expected).
                    //   2. Real-device farms (SauceLabs) — RP auto-created a bare "orphan" launch
                    //      from the first test-item POST before startLaunch ran, so it has none of
                    //      our attributes (no merge_group) and the post-run merge can't find it.
                    // Back-fill the attributes onto the existing launch so it merges in both cases.
                    if let httpError = error as? HTTPClientError,
                       case .httpError(let code, _) = httpError, code == 409 {
                        Logger.shared.info("✅ Launch already exists (409) — back-filling attributes onto it")
                        do {
                            try await reportingService.patchLaunchAttributes(uuid: launchUUID, attributes: attributes)
                        } catch {
                            Logger.shared.warning("⚠️  Could not back-fill attributes onto launch \(launchUUID): \(error.localizedDescription)")
                        }
                        return true
                    }
                    if attempt < maxAttempts {
                        let delay = UInt64(attempt) * 2_000_000_000
                        Logger.shared.warning("⚠️  startLaunch attempt \(attempt) failed: \(error.localizedDescription). Retrying...")
                        try? await Task.sleep(nanoseconds: delay)
                    } else {
                        Logger.shared.error("❌ startLaunch failed after \(maxAttempts) attempts: \(error.localizedDescription)")
                    }
                }
            }
            // All attempts exhausted — launch does not exist; consumers must not report.
            return false
        }
        self.launchGate = gate
    }
    
    /// A shared launch is created by whichever process reaches ReportPortal first, stamped with
    /// that device's clock. ReportPortal rejects an item that starts before its launch, and the
    /// async v2 API drops it without an error — a device whose clock lags the creator's by even
    /// half a second would lose every class it runs. Read the launch's stored start time and
    /// never stamp earlier than it.
    static func alignClock(withSharedLaunch uuid: String, using service: ReportingServiceProtocol) async {
        for attempt in 1...5 {
            if let start = try? await service.launchStartTime(uuid: uuid) {
                TimeHelper.clamp(notBefore: start)
                Logger.shared.info("🕒 Timestamps aligned to the shared launch start: \(start)")
                return
            }
            try? await Task.sleep(nanoseconds: UInt64(attempt) * 500_000_000)
        }
        Logger.shared.warning("⚠️ Could not read the shared launch's start time; a device clock lagging the creator's may lose items")
    }

    /// XCTest reports a skipped test as succeeded (`hasSucceeded == true`), so check the skip first.
    static func status(skipped: Bool, succeeded: Bool) -> TestStatus {
        if skipped { return .skipped }
        return succeeded ? .passed : .failed
    }

    static func buildEnhancedLaunchName(baseLaunchName: String, testPlanName: String?) -> String {
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

        // A filter can leave a class with no tests to run; XCTest still opens and closes it.
        guard testSuite.testCaseCount > 0 else {
            Logger.shared.info("⏭️ Skipping empty suite: '\(testSuite.name)'")
            return
        }
        
        Logger.shared.info("🔄 Processing suite: '\(testSuite.name)' (starting async Task)")
        
        let codeRef = (testSuite.tests.first as? XCTestCase).map { String(reflecting: type(of: $0)) } ?? testSuite.name

        enqueue(on: testSuite.name) {
            // Await the launch gate — guarantees launch creation finished. Skip reporting
            // if it failed: the launch doesn't exist, so child-item calls would all fail.
            guard let gate = self.launchGate else {
                Logger.shared.error("❌ launchGate is nil — testBundleWillStart was never called!")
                return
            }
            guard await gate.value else {
                Logger.shared.warning("⚠️  Launch was not created — skipping suite: \(testSuite.name)")
                return
            }

            // Get launch ID (synchronous access after launch is ready)
            let launchID = LaunchUUID.value
            
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
                operation.codeRef = codeRef
                // Retries of this class run in other processes: they must all report into one
                // suite, so it gets the same id everywhere instead of a fresh one per process.
                if self.collapseRetries && LaunchUUID.source != .generated {
                    operation.sharedUUID = LaunchUUID.sharedItemUUID(launchUUID: launchID, name: codeRef)
                }

                // Register suite in tracker with consistent identifier
                await self.operationTracker.registerSuite(operation, identifier: identifier)

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
                await self.operationTracker.updateSuite(operation, identifier: identifier)

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
        
        let testName = extractTestName(from: testCase)
        let className = String(describing: type(of: testCase))
        let codeRef = "\(String(reflecting: type(of: testCase))).\(testName)"

        enqueue(on: className) {
            // Await the launch gate — guarantees launch creation finished. Skip reporting
            // if it failed: the launch doesn't exist, so child-item calls would all fail.
            guard let gate = self.launchGate else {
                Logger.shared.error("❌ launchGate is nil — testBundleWillStart was never called!")
                return
            }
            guard await gate.value else {
                Logger.shared.warning("⚠️  Launch was not created — skipping test: \(testCase.name)")
                return
            }

            // Get launch ID
            let launchID = LaunchUUID.value
            
            do {
                let correlationID = UUID()
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
                guard let suiteID = await self.getCurrentSuiteID(for: className) else {
                    let activeSuites = await self.operationTracker.getAllSuiteIdentifiers()
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
                let metadata = self.collectTestMetadata()
                
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
                operation.codeRef = codeRef
                operation.attributes = self.testAttributes
                operation.retry = self.collapseRetries
                
                // Register test in tracker
                await self.operationTracker.registerTest(operation, identifier: identifier)
                
                // Start test in ReportPortal
                let testID = try await asyncService.startTest(operation: operation, launchID: launchID)
                
                // Update operation with test ID
                operation.testID = testID
                await self.operationTracker.updateTest(operation, identifier: identifier)
                
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
        // The suite's start ran earlier in this class's chain, so it is registered by now —
        // unless it failed to start. Don't wait: that would stall every later request of the class.
        if let suiteOp = await self.operationTracker.getSuite(identifier: className), !suiteOp.suiteID.isEmpty {
            return suiteOp.suiteID
        }
        Logger.shared.warning("Suite '\(className)' is not started")

        // If exact match failed after waiting, check all registered suites for potential matches
        // This handles edge cases where XCTest might provide different naming
        let allSuites = await self.operationTracker.getAllSuiteIdentifiers()
        Logger.shared.debug("Searching for suite matching class '\(className)' in: [\(allSuites.joined(separator: ", "))]")

        // Try to find a suite that contains the class name
        for suiteIdentifier in allSuites {
            if suiteIdentifier.contains(className) || className.contains(suiteIdentifier) {
                if let suiteOp = await self.operationTracker.getSuite(identifier: suiteIdentifier), !suiteOp.suiteID.isEmpty {
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
        let lineNumberString = issue.sourceCodeContext.location.map { " on line \($0.lineNumber)" } ?? ""
        reportFailure(of: testCase, message: "Test '\(String(describing: issue.description))' failed\(lineNumberString), \(issue.description)")
    }
    
    // For iOs 17+
    public func testCase(_ testCase: XCTestCase, didFailWithDescription description: String, inFile filePath: String?, atLine lineNumber: Int) {
        let fileInfo = filePath.map { " in \(URL(fileURLWithPath: $0).lastPathComponent)" } ?? ""
        reportFailure(of: testCase, message: "Test failed on line \(lineNumber)\(fileInfo): \(description)")
    }

    /// Log a failure and a screenshot of the screen at that moment on the failing test.
    private func reportFailure(of testCase: XCTestCase, message: String) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test failure for '\(testCase.name)' will not be reported to ReportPortal")
            return
        }

        // Take the screenshot now, not when the class's chain reaches the upload.
        #if canImport(UIKit)
        let screenshot = Task { @MainActor in XCUIScreen.main.screenshot().pngRepresentation }
        #endif

        let testName = extractTestName(from: testCase)
        let className = String(describing: type(of: testCase))
        let identifier = "\(className).\(testName)"

        enqueue(on: className) {
            let launchID = LaunchUUID.value

            guard let operation = await self.operationTracker.getTest(identifier: identifier) else {
                Logger.shared.warning("""
                    ⚠️ Cannot report test failure: Test operation not found for '\(identifier)'
                    Reason: Test may not have been registered successfully
                    Impact: Test failure details will not be visible in ReportPortal
                    """)
                return
            }

            do {
                try await asyncService.postLog(
                    message: message,
                    level: "error",
                    itemID: operation.testID,
                    launchID: launchID,
                    correlationID: operation.correlationID
                )

                #if canImport(UIKit)
                do {
                    let timestamp = Int64(Date().timeIntervalSince1970 * 1000)
                    try await asyncService.postScreenshot(
                        screenshotData: await screenshot.value,
                        filename: "failure_screenshot_\(timestamp).png",
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

        let testName = extractTestName(from: testCase)
        let className = String(describing: type(of: testCase))
        let identifier = "\(className).\(testName)"
        let status = RPListener.status(skipped: testCase.testRun?.hasBeenSkipped ?? false,
                                       succeeded: testCase.testRun?.hasSucceeded ?? false)

        // Finalize test with status update and cleanup
        enqueue(on: className) {
            // Retrieve test operation from tracker
            guard var operation = await self.operationTracker.getTest(identifier: identifier) else {
                Logger.shared.error("Test operation not found in tracker: \(identifier)")
                return
            }

            do {
                operation.status = status

                // Finish test in ReportPortal
                // Note: Screenshots are uploaded directly in failure methods, not here
                try await asyncService.finishTest(operation: operation)

                // Unregister test from tracker (cleanup)
                await self.operationTracker.unregisterTest(identifier: identifier)

                Logger.shared.info("Test finished: \(operation.testID) with status: \(status.rawValue)", correlationID: operation.correlationID)
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
            !testSuite.name.contains("Selected tests"),
            testSuite.testCaseCount > 0 else
        {
            return
        }
        
        let identifier = testSuite.name

        // Finalize suite with OperationTracker
        enqueue(on: identifier) {
            Logger.shared.info("🏁 testSuiteDidFinish called - Suite: '\(identifier)'")
            
            // Retrieve suite operation from tracker
            guard let operation = await self.operationTracker.getSuite(identifier: identifier) else {
                Logger.shared.error("❌ Suite operation not found in tracker: \(identifier)")
                return
            }

            // A shared suite may still be running tests on another device, and finishing it
            // would force-finish them. The launch finish closes it, with the status of its tests.
            if operation.sharedUUID != nil {
                await self.operationTracker.unregisterSuite(identifier: identifier)
                Logger.shared.info("🔗 Shared suite '\(identifier)' left open for the launch finish", correlationID: operation.correlationID)
                return
            }
            
            do {
                Logger.shared.info("📡 Finishing suite '\(identifier)' in ReportPortal...", correlationID: operation.correlationID)
                
                // Finish suite in ReportPortal
                try await asyncService.finishSuite(operation: operation)
                
                // Unregister suite from tracker (cleanup)
                await self.operationTracker.unregisterSuite(identifier: identifier)
                
                Logger.shared.info("✅ Suite finished: \(operation.suiteID)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("❌ Failed to finish suite '\(testSuite.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
        }
    }
    
    public func testBundleDidFinish(_ testBundle: Bundle) {
        Logger.shared.info("🏁 testBundleDidFinish called - Bundle: \(testBundle.bundleIdentifier ?? "unknown")")
        
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test bundle completion will not be reported to ReportPortal")
            return
        }
        
        Logger.shared.info("📦 Bundle finished - waiting for pending reporting, then finalizing launch")

        let pending = Array(classChains.values)
        let gate = launchGate
        let skipFinish = RPListener.resolveSkipFinish(from: testBundle)
        let done = DispatchSemaphore(value: 0)

        Task {
            for chain in pending {
                await chain.value
            }

            let launchID = LaunchUUID.value
            if await gate?.value != true {
                Logger.shared.warning("⚠️ Launch was not created — nothing to finalize")
            } else if skipFinish {
                Logger.shared.info("⏭️ RP_SKIP_FINISH is set — skipping launch finalization")
                Logger.shared.info("📋 Launch ID for manual/script finalization: \(launchID)")
            } else {
                do {
                    try await asyncService.finalizeLaunch(launchID: launchID)
                    Logger.shared.info("✅ Launch finalized successfully: \(launchID)")
                } catch {
                    Logger.shared.error("❌ Failed to finalize launch: \(error.localizedDescription)")
                }
            }
            done.signal()
        }

        // XCTest ends the process as soon as this returns, so wait here for the reporting still
        // in flight. Keep the main run loop turning meanwhile: blocking it would deadlock work
        // that needs the main actor, such as a failure screenshot.
        let deadline = Date().addingTimeInterval(RPListener.finalizationTimeout)
        while done.wait(timeout: .now()) == .timedOut {
            guard Date() < deadline else {
                Logger.shared.error("⚠️ Reporting did not finish within \(Int(RPListener.finalizationTimeout))s — results still in flight are lost")
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }

        XCTestObservationCenter.shared.removeTestObserver(self)
        Logger.shared.info("🛑 Test observer removed - execution complete")
    }

    // MARK: - SauceLabs Merge Support

    /// Resolve mergeGroup: (1) RP_MERGE_GROUP env var, (2) ReportPortalMergeGroup Info.plist.
    /// Static so it can be unit-tested without instantiating an observer.
    static func resolveMergeGroup(from testBundle: Bundle?) -> String? {
        // Trim and treat whitespace-only as "not set" — consistent with LaunchUUID and
        // the ci_run_id resolution, so RP_MERGE_GROUP=" " falls through instead of
        // becoming a bogus group attribute.
        if let envValue = ProcessInfo.processInfo.environment["RP_MERGE_GROUP"] {
            let trimmed = envValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Logger.shared.info("📎 merge_group from env var: \(trimmed)")
                return trimmed
            }
        }
        if let plistValue = testBundle?.object(forInfoDictionaryKey: "ReportPortalMergeGroup") as? String {
            let trimmed = plistValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                Logger.shared.info("📎 merge_group from Info.plist: \(trimmed)")
                return trimmed
            }
        }
        return nil
    }

    /// Resolve skipFinish: (1) RP_SKIP_FINISH env var, (2) ReportPortalSkipFinish Info.plist, (3) false.
    /// Accepts both String ("true"/"yes"/"1" vs "false"/"no"/"0") and Boolean values so that an
    /// explicit RP_SKIP_FINISH=false is honored, and a String "YES" in Info.plist is not silently
    /// ignored. Static so it can be unit-tested without instantiating an observer.
    static func resolveSkipFinish(from testBundle: Bundle?) -> Bool {
        if let envValue = ProcessInfo.processInfo.environment["RP_SKIP_FINISH"],
           let parsed = parseBoolFlag(envValue) {
            Logger.shared.info("⏭️ skipFinish from env var: \(parsed)")
            return parsed
        }
        if let plistValue = testBundle?.object(forInfoDictionaryKey: "ReportPortalSkipFinish"),
           let parsed = parseBoolFlag(plistValue) {
            Logger.shared.info("⏭️ skipFinish from Info.plist: \(parsed)")
            return parsed
        }
        // A launch UUID compiled into the Info.plist is shared by every shard of the run,
        // so this process does not own the launch: finalizing it here would close the
        // launch under the shards still reporting, and ReportPortal force-finishes every
        // still-running item with the finish request's status when a launch is finished. The run is closed
        // once, from CI, after all shards are done.
        if LaunchUUID.source == .infoPlist {
            Logger.shared.info("⏭️ skipFinish: launch UUID came from Info.plist (shared launch — CI finalizes it)")
            return true
        }
        return false
    }

    /// Resolve collapseRetries: (1) RP_COLLAPSE_RETRIES env var, (2) ReportPortalCollapseRetries
    /// Info.plist, (3) false. Opt-in because the same test reported twice in one launch is either
    /// a retry (one row) or the same suite on several device models (separate rows), and only the
    /// setup knows which.
    static func resolveCollapseRetries(from testBundle: Bundle?) -> Bool {
        if let envValue = ProcessInfo.processInfo.environment["RP_COLLAPSE_RETRIES"],
           let parsed = parseBoolFlag(envValue) {
            Logger.shared.info("🔁 collapseRetries from env var: \(parsed)")
            return parsed
        }
        if let plistValue = testBundle?.object(forInfoDictionaryKey: "ReportPortalCollapseRetries"),
           let parsed = parseBoolFlag(plistValue) {
            Logger.shared.info("🔁 collapseRetries from Info.plist: \(parsed)")
            return parsed
        }
        return false
    }

    /// Parse a boolean from a Bool/NSNumber or a String ("true"/"yes"/"1" → true,
    /// "false"/"no"/"0" → false). Returns nil when absent or unrecognized, so the next
    /// resolution tier (Info.plist, then the default) applies.
    static func parseBoolFlag(_ value: Any?) -> Bool? {
        if let boolValue = value as? Bool {
            return boolValue
        }
        if let stringValue = value as? String {
            switch stringValue.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "1": return true
            case "false", "no", "0": return false
            default: return nil
            }
        }
        return nil
    }
}
