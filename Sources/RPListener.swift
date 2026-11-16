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

    /// Reporting work, ordered by XCTest callback order (callbacks arrive serially on the main
    /// thread). A suite starts before its tests; each test's own requests run in order (start →
    /// logs → finish), so it is never finished before its start returned an id; and a suite
    /// finishes only after every request of its tests, since ReportPortal would force-finish a
    /// still-running test with the suite's status. Different tests still report concurrently.
    /// A task's value is the item as its request left it (`nil`: not started); the next request reads it.
    private var suiteStarts: [String: Task<SuiteOperation?, Never>] = [:]
    private var testChains: [String: Task<TestOperation?, Never>] = [:]
    private var suiteFinishes: [String: Task<Void, Never>] = [:]

    /// `ReportPortalCollapseRetries`: mark tests as retries so ReportPortal nests earlier
    /// attempts of a test under its last one.
    private var collapseRetries = false

    /// Device and OS on every test of a shared launch, so each attempt shows where it ran.
    private var testAttributes: [[String: String]] = []

    /// Upper bound on how long the end of the bundle waits for reporting still in flight.
    static let finalizationTimeout: TimeInterval = 120

    /// A class that runs again in the same process (test iterations) starts its suite only
    /// after the previous run's suite finished.
    private func enqueueSuiteStart(_ className: String, _ work: @escaping () async -> SuiteOperation?) {
        let previousFinish = suiteFinishes[className]
        suiteStarts[className] = Task {
            await previousFinish?.value
            return await work()
        }
    }

    /// `identifier` is `Module.Class.method`. Each request waits for the test's previous request and for
    /// the latest start of its suite: when a whole class runs again in the same process (test
    /// iterations), the repeated test must go under the new suite, not race it.
    private func enqueue(test identifier: String, in className: String,
                         _ work: @escaping (SuiteOperation?, TestOperation?) async -> TestOperation?) {
        let previous = testChains[identifier]
        let suiteStart = suiteStarts[className]
        testChains[identifier] = Task {
            let suite = await suiteStart?.value ?? nil
            let test = await previous?.value ?? nil
            return await work(suite, test)
        }
    }

    /// `work` gets the suite and the tests this process started in it.
    private func enqueueSuiteFinish(_ className: String, _ work: @escaping (SuiteOperation, Set<String>) async -> Void) {
        let tests = testChains.filter { $0.key.hasPrefix(className + ".") }.map { $0.value }
        let start = suiteStarts[className]
        suiteFinishes[className] = Task {
            var testIDs = Set<String>()
            for task in tests {
                if let test = await task.value { testIDs.insert(test.testID) }
            }
            guard let suite = await start?.value ?? nil else { return }
            await work(suite, testIDs)
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
        Logger.shared.info("📦 Launch UUID: \(launchUUID) (from \(LaunchUUID.source))")

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
                    // 409 = a launch with this UUID already exists: report into it. ReportPortal's
                    // asynchronous v2 API answers a duplicate start with 201 instead.
                    if let httpError = error as? HTTPClientError,
                       case .httpError(let code, _) = httpError, code == 409 {
                        Logger.shared.info("✅ Launch already exists (409) — reporting into it")
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
        if let start = await TimeHelper.clamp(toStoredStart: { try await service.launchStartTime(uuid: uuid) }) {
            Logger.shared.info("🕒 Timestamps aligned to the shared launch start: \(start)")
        } else {
            Logger.shared.warning("⚠️ Could not read the shared launch's start time; a device clock lagging the creator's may lose items")
        }
    }

    /// Whether this process finishes a suite shared with other processes: only while none of its
    /// tests runs elsewhere, since finishing a suite force-finishes its running tests as interrupted.
    /// So the process that leaves the class last closes it, and a retry that joins later finishes it
    /// again, so ReportPortal recomputes its status. This process's own tests can still read as
    /// running (v2 reporting is asynchronous), so they don't count, and another device's test that
    /// just finished gets a moment to land. A suite that can't be read stays open; the launch finish
    /// closes it.
    static func noTestRunsElsewhere(inSuite uuid: String, own: Set<String>, using service: ReportingServiceProtocol,
                                    pause: UInt64 = 1_000_000_000) async -> Bool {
        for attempt in 1...3 {
            if let running = try? await service.runningTests(inSuite: uuid), running.allSatisfy(own.contains) {
                return true
            }
            if attempt < 3 {
                try? await Task.sleep(nanoseconds: pause)
            }
        }
        return false
    }

    /// The class a suite runs, named as its tests' callbacks name it (`Module.Outer.Class`); nil for
    /// XCTest's container suites (All tests, the `.xctest` bundle), which hold suites, and for a class
    /// filtered down to no tests.
    static func testClass(of suite: XCTestSuite) -> String? {
        (suite.tests.first as? XCTestCase).map { String(reflecting: type(of: $0)) }
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
    
    public func testSuiteWillStart(_ testSuite: XCTestSuite) {
        Logger.shared.info("📋 testSuiteWillStart called: '\(testSuite.name)'")

        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test suite '\(testSuite.name)' will not be reported to ReportPortal")
            return
        }

        guard let codeRef = RPListener.testClass(of: testSuite) else {
            Logger.shared.info("⏭️ Skipping suite: '\(testSuite.name)'")
            return
        }
        
        Logger.shared.info("🔄 Processing suite: '\(testSuite.name)' (starting async Task)")
        
        // Retries of this class run in other processes: they must all report into one suite,
        // so it gets the same id everywhere instead of a fresh one per process.
        let sharesSuite = collapseRetries && LaunchUUID.source != .generated

        enqueueSuiteStart(codeRef) {
            // Await the launch gate — guarantees launch creation finished. Skip reporting
            // if it failed: the launch doesn't exist, so child-item calls would all fail.
            guard let gate = self.launchGate else {
                Logger.shared.error("❌ launchGate is nil — testBundleWillStart was never called!")
                return nil
            }
            guard await gate.value else {
                Logger.shared.warning("⚠️  Launch was not created — skipping suite: \(testSuite.name)")
                return nil
            }

            // Get launch ID (synchronous access after launch is ready)
            let launchID = LaunchUUID.value
            
            do {
                let correlationID = UUID()

                // DIAGNOSTIC: Log suite details to understand naming
                Logger.shared.info("""
                    📦 SUITE STARTING:
                    - identifier: '\(codeRef)'
                    - testCount: \(testSuite.testCaseCount)
                    """, correlationID: correlationID)

                // Create suite operation
                var operation = SuiteOperation(
                    correlationID: correlationID,
                    suiteID: "", // Will be set after API call
                    suiteName: testSuite.name
                )
                operation.codeRef = codeRef
                if sharesSuite {
                    operation.sharedUUID = LaunchUUID.sharedItemUUID(launchUUID: launchID, name: codeRef)
                }

                let apiStartTime = Date()
                operation.suiteID = try await asyncService.startSuite(operation: operation, launchID: launchID)
                Logger.shared.info("📡 API call completed in \(Int(Date().timeIntervalSince(apiStartTime) * 1000))ms", correlationID: correlationID)

                Logger.shared.info("✅ Suite started: \(operation.suiteID)", correlationID: correlationID)
                return operation
            } catch {
                Logger.shared.error("Failed to start suite '\(testSuite.name)': \(error.localizedDescription)")
                return nil
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
        let className = String(reflecting: type(of: testCase))
        let identifier = "\(className).\(testName)"
        let attributes = testAttributes
        let retry = collapseRetries

        enqueue(test: identifier, in: className) { suite, _ in
            // Await the launch gate — guarantees launch creation finished. Skip reporting
            // if it failed: the launch doesn't exist, so child-item calls would all fail.
            guard let gate = self.launchGate else {
                Logger.shared.error("❌ launchGate is nil — testBundleWillStart was never called!")
                return nil
            }
            guard await gate.value else {
                Logger.shared.warning("⚠️  Launch was not created — skipping test: \(testCase.name)")
                return nil
            }

            // Get launch ID
            let launchID = LaunchUUID.value
            
            do {
                let correlationID = UUID()

                // DIAGNOSTIC: Log test details
                Logger.shared.info("""
                    🧪 TEST STARTING:
                    - testCase.name: '\(testCase.name)'
                    - testName: '\(testName)'
                    - className: '\(className)'
                    - Looking for suite: '\(className)'
                    """, correlationID: correlationID)

                guard let suite = suite else {
                    Logger.shared.error("""
                        ❌ TEST REGISTRATION FAILED: '\(identifier)'
                        Reason: suite '\(className)' did not start
                        Impact: Cannot establish test hierarchy in ReportPortal
                        """)
                    return nil
                }
                
                // Create test operation
                var operation = TestOperation(
                    correlationID: correlationID,
                    testID: "", // Will be set after API call
                    suiteID: suite.suiteID,
                    testName: testName
                )
                operation.codeRef = identifier
                operation.attributes = attributes
                operation.retry = retry
                
                // Start test in ReportPortal
                operation.testID = try await asyncService.startTest(operation: operation, launchID: launchID)

                Logger.shared.info("Test started: \(operation.testID)", correlationID: correlationID)
                return operation
            } catch {
                Logger.shared.error("Failed to start test '\(testCase.name)': \(error.localizedDescription)")
                return nil
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
        let className = String(reflecting: type(of: testCase))
        let identifier = "\(className).\(testName)"

        enqueue(test: identifier, in: className) { _, test in
            let launchID = LaunchUUID.value

            guard let operation = test else {
                Logger.shared.warning("""
                    ⚠️ Cannot report test failure: Test operation not found for '\(identifier)'
                    Reason: Test may not have been registered successfully
                    Impact: Test failure details will not be visible in ReportPortal
                    """)
                return nil
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
            return operation
        }
    }
    
    public func testCaseDidFinish(_ testCase: XCTestCase) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test completion for '\(testCase.name)' will not be reported to ReportPortal")
            return
        }

        let testName = extractTestName(from: testCase)
        let className = String(reflecting: type(of: testCase))
        let identifier = "\(className).\(testName)"
        let status = RPListener.status(skipped: testCase.testRun?.hasBeenSkipped ?? false,
                                       succeeded: testCase.testRun?.hasSucceeded ?? false)

        // Finalize test with status update
        enqueue(test: identifier, in: className) { _, test in
            guard var operation = test else {
                Logger.shared.error("Test operation not found: \(identifier)")
                return nil
            }

            do {
                operation.status = status

                // Finish test in ReportPortal
                // Note: Screenshots are uploaded directly in failure methods, not here
                try await asyncService.finishTest(operation: operation)

                Logger.shared.info("Test finished: \(operation.testID) with status: \(status.rawValue)", correlationID: operation.correlationID)
            } catch {
                Logger.shared.error("Failed to finish test '\(testCase.name)': \(error.localizedDescription)", correlationID: operation.correlationID)
            }
            return operation
        }
    }
    
    public func testSuiteDidFinish(_ testSuite: XCTestSuite) {
        guard let asyncService = reportingService else {
            Logger.shared.warning("⚠️ Reporting disabled: Test suite completion for '\(testSuite.name)' will not be reported to ReportPortal")
            return
        }
        
        guard let identifier = RPListener.testClass(of: testSuite) else { return }

        // Finalize suite
        enqueueSuiteFinish(identifier) { operation, ownTests in
            Logger.shared.info("🏁 testSuiteDidFinish called - Suite: '\(identifier)'")

            if let sharedUUID = operation.sharedUUID {
                guard await RPListener.noTestRunsElsewhere(inSuite: sharedUUID, own: ownTests, using: asyncService) else {
                    Logger.shared.info("🔗 Shared suite '\(identifier)' left open: a test of it is running on another device", correlationID: operation.correlationID)
                    return
                }
            }
            
            do {
                Logger.shared.info("📡 Finishing suite '\(identifier)' in ReportPortal...", correlationID: operation.correlationID)
                
                // Finish suite in ReportPortal
                try await asyncService.finishSuite(operation: operation)
                
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

        let starts = Array(suiteStarts.values), chains = Array(testChains.values), finishes = Array(suiteFinishes.values)
        let gate = launchGate
        let skipFinish = RPListener.resolveSkipFinish(from: testBundle)
        let done = DispatchSemaphore(value: 0)

        Task {
            for task in starts { _ = await task.value }
            for task in chains { _ = await task.value }
            for task in finishes { await task.value }

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
        while done.wait(timeout: .now() + .milliseconds(10)) == .timedOut {
            guard Date() < deadline else {
                Logger.shared.error("⚠️ Reporting did not finish within \(Int(RPListener.finalizationTimeout))s — results still in flight are lost")
                break
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.01))
        }

        // Not while XCTest is still delivering this callback to its observers: removing one
        // mid-delivery can skip XCTest's own, and xcodebuild then never hears the run finished.
        DispatchQueue.main.async {
            XCTestObservationCenter.shared.removeTestObserver(self)
        }
        Logger.shared.info("🛑 Reporting finished - execution complete")
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
        if let flag = boolFlag(env: "RP_SKIP_FINISH", plistKey: "ReportPortalSkipFinish", from: testBundle) {
            return flag
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
        boolFlag(env: "RP_COLLAPSE_RETRIES", plistKey: "ReportPortalCollapseRetries", from: testBundle) ?? false
    }

    /// A boolean setting: the `env` variable first, then `plistKey` in the test bundle's
    /// Info.plist. `nil` when neither holds a recognized value.
    static func boolFlag(env: String, plistKey: String, from testBundle: Bundle?) -> Bool? {
        if let parsed = parseBoolFlag(ProcessInfo.processInfo.environment[env]) {
            Logger.shared.info("⚙️ \(env) from env var: \(parsed)")
            return parsed
        }
        if let parsed = parseBoolFlag(testBundle?.object(forInfoDictionaryKey: plistKey)) {
            Logger.shared.info("⚙️ \(plistKey) from Info.plist: \(parsed)")
            return parsed
        }
        return nil
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
