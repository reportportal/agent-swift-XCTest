//  Copyright 2026 EPAM Systems
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

import XCTest
@testable import ReportPortalAgent

// MARK: - resolveMergeGroup / resolveSkipFinish Tests

/// Tests for SauceLabs merge support: merge_group and skipFinish resolution.
/// These are pure *static* resolvers (env var → Info.plist → default), so they are
/// exercised without instantiating `RPListener` — instantiating it would register a
/// process-global `XCTestObservation` observer that never gets removed.
///
/// Environment variables are process-global and cannot be set/unset from Swift, so the
/// env-var priority path is validated by `ValidationTest` on SauceLabs real devices; here
/// we cover the Info.plist fallback, nil-bundle, and value-parsing paths.
final class SauceLabsSupportTests: XCTestCase {

    // MARK: - resolveMergeGroup

    func testResolveMergeGroup_NoPlistKey_ReturnsNil() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_MERGE_GROUP"] != nil,
                      "RP_MERGE_GROUP env var is set; env-var path tested on SauceLabs real devices")
        let bundle = Bundle(for: type(of: self))
        XCTAssertNil(RPListener.resolveMergeGroup(from: bundle),
                     "Should return nil when neither env var nor Info.plist key is set")
    }

    func testResolveMergeGroup_MainBundle_ReturnsNil() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_MERGE_GROUP"] != nil,
                      "RP_MERGE_GROUP env var is set; env-var path tested on SauceLabs real devices")
        XCTAssertNil(RPListener.resolveMergeGroup(from: Bundle.main))
    }

    func testResolveMergeGroup_NilBundle_ReturnsNil() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_MERGE_GROUP"] != nil,
                      "RP_MERGE_GROUP env var is set; env-var path tested on SauceLabs real devices")
        XCTAssertNil(RPListener.resolveMergeGroup(from: nil))
    }

    // MARK: - resolveSkipFinish

    func testResolveSkipFinish_NoPlistKey_ReturnsFalse() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_SKIP_FINISH"] != nil,
                      "RP_SKIP_FINISH env var is set; env-var path tested on SauceLabs real devices")
        let bundle = Bundle(for: type(of: self))
        XCTAssertFalse(RPListener.resolveSkipFinish(from: bundle),
                       "Should return false when neither env var nor Info.plist key is set")
    }

    func testResolveSkipFinish_NilBundle_ReturnsFalse() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_SKIP_FINISH"] != nil,
                      "RP_SKIP_FINISH env var is set; env-var path tested on SauceLabs real devices")
        XCTAssertFalse(RPListener.resolveSkipFinish(from: nil), "Should return false when bundle is nil")
    }

    func testResolveSkipFinish_MainBundle_ReturnsFalse() throws {
        try XCTSkipIf(ProcessInfo.processInfo.environment["RP_SKIP_FINISH"] != nil,
                      "RP_SKIP_FINISH env var is set; env-var path tested on SauceLabs real devices")
        XCTAssertFalse(RPListener.resolveSkipFinish(from: Bundle.main),
                       "Should return false for main bundle without plist key")
    }

    // MARK: - parseBoolFlag (String/Bool tolerance — the core of the skipFinish fix)

    func testParseBoolFlag_TruthyStrings() {
        for value in ["true", "TRUE", "Yes", "yes", "1", " true "] {
            XCTAssertEqual(RPListener.parseBoolFlag(value), true, "\"\(value)\" should parse as true")
        }
    }

    func testParseBoolFlag_FalsyStrings() {
        // The regression this guards: "false"/"no"/"0" must NOT be treated as true.
        for value in ["false", "FALSE", "No", "no", "0", " false "] {
            XCTAssertEqual(RPListener.parseBoolFlag(value), false, "\"\(value)\" should parse as false")
        }
    }

    func testParseBoolFlag_BoolValues() {
        XCTAssertEqual(RPListener.parseBoolFlag(true), true)
        XCTAssertEqual(RPListener.parseBoolFlag(false), false)
    }

    func testParseBoolFlag_UnrecognizedReturnsNil() {
        XCTAssertNil(RPListener.parseBoolFlag("maybe"))
        XCTAssertNil(RPListener.parseBoolFlag(""))
        XCTAssertNil(RPListener.parseBoolFlag(nil))
    }
}

// MARK: - finalizeLaunch 409-only Non-Fatal Tests

/// Verifies the predicate that `ReportingService.finalizeLaunch` uses: only HTTP 409
/// (launch already finished) is non-fatal; every other HTTP status and every non-HTTP
/// error is fatal and must propagate.
final class IdempotentFinalizeLaunchTests: XCTestCase {

    func testHTTPClientError_409_IsNonFatal() {
        XCTAssertTrue(HTTPClientError.httpError(statusCode: 409, body: "already finished").isLaunchAlreadyFinished,
                      "409 is the only non-fatal finalize status")
    }

    func testHTTPClientError_OtherClientErrors_AreFatal() {
        for code in [400, 401, 403, 404, 422] {
            XCTAssertFalse(HTTPClientError.httpError(statusCode: code, body: "error").isLaunchAlreadyFinished,
                           "Status \(code) must be fatal (only 409 is non-fatal)")
        }
    }

    func testHTTPClientError_5xx_AreFatal() {
        for code in [500, 502, 503] {
            XCTAssertFalse(HTTPClientError.httpError(statusCode: code, body: "server error").isLaunchAlreadyFinished,
                           "Status \(code) must be fatal")
        }
    }

    func testHTTPClientError_NetworkError_IsFatal() {
        XCTAssertFalse(HTTPClientError.networkError(NSError(domain: "test", code: -1)).isLaunchAlreadyFinished,
                       "Network errors must propagate")
    }

    func testHTTPClientError_DecodingError_IsFatal() {
        XCTAssertFalse(HTTPClientError.decodingError("bad json").isLaunchAlreadyFinished,
                       "Decoding errors must propagate")
    }
}

// MARK: - Orphan-launch attribute back-fill endpoints

/// Verifies the two endpoints behind `patchLaunchAttributes`, which back-fills attributes
/// (e.g. `merge_group`) onto an orphan launch when `startLaunch` returns 409.
final class OrphanLaunchBackfillEndpointTests: XCTestCase {

    func testGetLaunchByUuidEndPoint_PathAndMethod() {
        let endPoint = GetLaunchByUuidEndPoint(uuid: "abc-123")
        XCTAssertEqual(endPoint.method, .get)
        XCTAssertEqual(endPoint.relativePath, "launch/uuid/abc-123",
                       "Must resolve the numeric id via GET launch/uuid/{uuid}")
    }

    func testUpdateLaunchEndPoint_PathMethodAndAttributes() {
        let attributes = [
            ["key": "merge_group", "value": "regression-42"],
            ["key": "ci_run_id", "value": "42"]
        ]
        let endPoint = UpdateLaunchEndPoint(launchID: 777, attributes: attributes)

        XCTAssertEqual(endPoint.method, .put)
        XCTAssertEqual(endPoint.relativePath, "launch/777/update",
                       "Update is keyed by the numeric launch id, not the UUID")

        let sent = endPoint.parameters["attributes"] as? [[String: String]]
        XCTAssertEqual(sent?.count, 2)
        XCTAssertEqual(sent?.first?["key"], "merge_group")
        XCTAssertEqual(sent?.first?["value"], "regression-42")
    }
}

// MARK: - No legacy "tags" field (the REAL "launch lost all attributes" bug)

/// ReportPortal's `StartRQ` declares `@JsonAlias({"attributes","tags"})` — both JSON fields
/// deserialize into the SAME server-side property, and Jackson keeps whichever appears LAST
/// in the document. Swift dictionaries serialize in per-process random key order, so a body
/// containing both fields randomly lost ALL keyed attributes (incl. `merge_group`) whenever
/// "tags" serialized after "attributes". These tests pin that the legacy field is never sent.
final class NoLegacyTagsFieldTests: XCTestCase {

    func testStartLaunchEndPoint_DoesNotSendLegacyTagsField() {
        let endPoint = StartLaunchEndPoint(
            launchName: "L",
            tags: ["stg2"],
            mode: .default,
            attributes: [["key": "merge_group", "value": "regression-1"]],
            uuid: "u-1"
        )
        XCTAssertNil(endPoint.parameters["tags"],
                     "\"tags\" is a @JsonAlias of \"attributes\" on the server; sending both randomly clobbers attributes")
        let attrs = endPoint.parameters["attributes"] as? [[String: String]]
        XCTAssertEqual(attrs?.first?["key"], "merge_group",
                       "Keyed attributes must be preserved in the body")
    }

    func testStartItemEndPoint_DoesNotSendLegacyTagsField() {
        let endPoint = StartItemEndPoint(itemName: "Suite", launchID: "u-1", type: .suite)
        XCTAssertNil(endPoint.parameters["tags"],
                     "An empty \"tags\": [] can wipe item attributes via the same @JsonAlias clobber")
    }
}

// MARK: - Launch-gate ordering (the "attribute-less orphan / N of 6" bug)

/// Records the ORDER in which `RPListener` calls ReportPortal, so a test can prove the launch
/// is created BEFORE any suite/test item is sent. If a suite/test is sent first, ReportPortal
/// auto-creates a bare launch with no `merge_group` — the orphan that the post-run merge can't
/// find. `startLaunch` sleeps briefly to mimic network latency, so a *missing* gate-await would
/// visibly record a suite before the launch.
final class RecordingReportingService: ReportingServiceProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var _calls: [String] = []
    private var _launchAttributes: [[String: String]] = []

    /// Ordered log of operations, e.g. ["startLaunch", "startSuite", ...].
    var calls: [String] { withLock { _calls } }
    /// The attributes passed to `startLaunch` (to assert `merge_group` is sent with the launch).
    var launchAttributes: [[String: String]] { withLock { _launchAttributes } }

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }

    private func record(_ op: String) { withLock { _calls.append(op) } }

    func startLaunch(name: String, tags: [String], attributes: [[String: String]], uuid: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms: make a missing gate-await observable
        withLock { _launchAttributes = attributes }
        record("startLaunch")
        return uuid
    }
    func patchLaunchAttributes(uuid: String, attributes: [[String: String]]) async throws { record("patchLaunchAttributes") }
    func launchStartTime(uuid: String) async throws -> Date? { record("launchStartTime"); return nil }
    func startSuite(operation: SuiteOperation, launchID: String) async throws -> String { record("startSuite"); return UUID().uuidString }
    func finishSuite(operation: SuiteOperation) async throws { record("finishSuite") }
    func startTest(operation: TestOperation, launchID: String) async throws -> String {
        try? await Task.sleep(nanoseconds: 50_000_000) // 50ms: make out-of-order finishes observable
        record("startTest")
        return UUID().uuidString
    }
    func finishTest(operation: TestOperation) async throws { record("finishTest") }
    func postLog(message: String, level: String, itemID: String, launchID: String, correlationID: UUID?) async throws { record("postLog") }
    func postScreenshot(screenshotData: Data, filename: String, itemID: String, launchID: String, correlationID: UUID?) async throws { record("postScreenshot") }
    func finalizeLaunch(launchID: String) async throws { record("finalizeLaunch") }
}

/// Drives the real `RPListener` XCTest callbacks (via a test init that skips observer
/// registration) against the recording double, and asserts the launch-before-items ordering.
final class LaunchGateOrderingTests: XCTestCase {

    private func makeConfig() -> AgentConfiguration {
        AgentConfiguration(
            reportPortalURL: URL(string: "https://example.invalid")!,
            projectName: "proj",
            launchName: "Launch",
            shouldSendReport: true,
            portalToken: "token",
            tags: [],
            launchMode: .default,
            testNameRules: []
        )
    }

    /// A class suite with one test: the agent doesn't report suites with nothing to run.
    private func suite(named name: String) -> XCTestSuite {
        let suite = XCTestSuite(name: name)
        suite.addTest(ReportingOrderTests.OrderingSample(selector: #selector(ReportingOrderTests.OrderingSample.sample)))
        return suite
    }

    /// Poll until `condition` holds or the timeout elapses (RPListener fires unstructured Tasks).
    private func wait(timeout: TimeInterval = 5, until condition: @escaping () -> Bool) async {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try? await Task.sleep(nanoseconds: 25_000_000)
        }
    }

    func testLaunchIsCreatedBeforeAnySuiteIsSent() async {
        setenv("RP_MERGE_GROUP", "test-mg-ordering", 1)
        defer { unsetenv("RP_MERGE_GROUP") }

        let recorder = RecordingReportingService()
        let listener = RPListener(injectedConfiguration: makeConfig(), makeReportingService: { _ in recorder })

        listener.testBundleWillStart(Bundle(for: RecordingReportingService.self))
        listener.testSuiteWillStart(suite(named: "CheckoutFeatureTests"))

        await wait { recorder.calls.contains("startSuite") }

        let calls = recorder.calls
        guard let launchIdx = calls.firstIndex(of: "startLaunch") else {
            return XCTFail("startLaunch was never called — launch not created. Calls: \(calls)")
        }
        guard let suiteIdx = calls.firstIndex(of: "startSuite") else {
            return XCTFail("startSuite was never called within timeout. Calls: \(calls)")
        }
        XCTAssertLessThan(launchIdx, suiteIdx,
            "Launch must be created BEFORE any suite is sent (else RP creates an attribute-less orphan). Order: \(calls)")
        XCTAssertTrue(
            recorder.launchAttributes.contains { $0["key"] == "merge_group" && $0["value"] == "test-mg-ordering" },
            "merge_group must be sent WITH startLaunch so the launch is mergeable. Got: \(recorder.launchAttributes)")

        withExtendedLifetime(listener) {}
    }

    func testEveryConcurrentListenerCreatesItsLaunchFirst() async {
        setenv("RP_MERGE_GROUP", "test-mg-parallel", 1)
        defer { unsetenv("RP_MERGE_GROUP") }

        // Simulate N parallel "devices": N independent listeners, each with its own launch.
        let deviceCount = 8
        var recorders: [RecordingReportingService] = []
        var listeners: [RPListener] = []
        for i in 0..<deviceCount {
            let recorder = RecordingReportingService()
            let listener = RPListener(injectedConfiguration: makeConfig(), makeReportingService: { _ in recorder })
            recorders.append(recorder)
            listeners.append(listener)
            listener.testBundleWillStart(Bundle(for: RecordingReportingService.self))
            listener.testSuiteWillStart(suite(named: "Device\(i)Tests"))
        }

        await wait(timeout: 10) { recorders.allSatisfy { $0.calls.contains("startSuite") } }

        for (i, recorder) in recorders.enumerated() {
            let calls = recorder.calls
            guard let launchIdx = calls.firstIndex(of: "startLaunch"),
                  let suiteIdx = calls.firstIndex(of: "startSuite") else {
                XCTFail("Device \(i): missing startLaunch/startSuite within timeout. Calls: \(calls)")
                continue
            }
            XCTAssertLessThan(launchIdx, suiteIdx,
                "Device \(i): a suite was sent before the launch was created. Order: \(calls)")
        }

        withExtendedLifetime(listeners) {}
    }
}

// MARK: - LaunchUUID resolution

/// The launch UUID may be supplied through the test bundle's `Info.plist`, because on
/// real-device farms that is the only channel that reaches every shard. Resolution is a
/// static resolver (env var → Info.plist → nil) so it is testable without touching the
/// memoized per-process value.
final class LaunchUUIDTests: XCTestCase {

    func testConfiguredLaunchUUID_NothingSet_ReturnsNil() {
        // The unit bundle carries no ReportPortalLaunchUUID, so the launch is per-process.
        XCTAssertNil(LaunchUUID.configuredLaunchUUID(from: Bundle(for: LaunchUUIDTests.self)))
    }

    func testConfiguredLaunchUUID_EnvVarWins() {
        setenv("RP_LAUNCH_UUID", "run-42-1", 1)
        defer { unsetenv("RP_LAUNCH_UUID") }

        let resolved = LaunchUUID.configuredLaunchUUID(from: Bundle(for: LaunchUUIDTests.self))
        XCTAssertEqual(resolved?.0, "run-42-1")
        XCTAssertEqual(resolved?.1, .environment)
    }

    func testConfiguredLaunchUUID_TrimsAndTreatsBlankAsAbsent() {
        setenv("RP_LAUNCH_UUID", "  run-42-1\n", 1)
        XCTAssertEqual(LaunchUUID.configuredLaunchUUID(from: nil)?.0, "run-42-1",
                       "whitespace must not split one run into two launches")

        // An unexpanded $(RP_LAUNCH_UUID) build setting arrives as an empty string; it must
        // not become the launch id.
        setenv("RP_LAUNCH_UUID", "   ", 1)
        defer { unsetenv("RP_LAUNCH_UUID") }
        XCTAssertNil(LaunchUUID.configuredLaunchUUID(from: nil))
    }

    func testSkipFinish_StaysOffWhenNoLaunchUUIDWasSupplied() {
        // Nothing supplied the launch UUID, so this process still owns finalizing it.
        XCTAssertFalse(RPListener.resolveSkipFinish(from: Bundle(for: LaunchUUIDTests.self)))
    }
}

final class TimeHelperTests: XCTestCase {

    func testDateFromServer_ParsesBothReportPortalFormats() {
        XCTAssertEqual(TimeHelper.date(fromServer: "2026-09-07T11:37:03.436Z")?.timeIntervalSince1970 ?? 0,
                       1_788_781_023.436, accuracy: 0.0005)
        XCTAssertEqual(TimeHelper.date(fromServer: "2026-09-07T13:28:14Z")?.timeIntervalSince1970,
                       1_788_787_694)
        XCTAssertNil(TimeHelper.date(fromServer: nil))
        XCTAssertNil(TimeHelper.date(fromServer: "1788781023436"))
    }

    func testLaunchDecodes_EpochMillisecondsAndIsoTimestamps() throws {
        // ReportPortal 5.15 returned this exact shape for a launch: numeric timestamps.
        let numeric = #"{"id":46,"uuid":"run-1","startTime":1791826312000,"endTime":1791826450000,"lastModified":1791826270109,"statistics":{"executions":{},"defects":{}},"attributes":[]}"#
        let launch = try JSONDecoder().decode(Launch.self, from: Data(numeric.utf8))
        XCTAssertEqual(launch.startTime?.date?.timeIntervalSince1970, 1_791_826_312)

        let iso = #"{"id":10,"startTime":"2026-09-07T11:37:03.436Z"}"#
        XCTAssertEqual(try JSONDecoder().decode(Launch.self, from: Data(iso.utf8)).startTime?.date?.timeIntervalSince1970 ?? 0,
                       1_788_781_023.436, accuracy: 0.0005)
    }
}

// MARK: - Statuses ReportPortal shows

/// ReportPortal keeps an explicit status over the one it would derive, so containers and the
/// launch must finish WITHOUT one, and a test's own status must be the real one.
final class ReportedStatusTests: XCTestCase {

    func testSkippedTestIsReportedAsSkipped() {
        // XCTest reports a skipped test with hasSucceeded == true.
        XCTAssertEqual(RPListener.status(skipped: true, succeeded: true), .skipped,
                       "a skipped test must not reach ReportPortal as PASSED")
        XCTAssertEqual(RPListener.status(skipped: false, succeeded: true), .passed)
        XCTAssertEqual(RPListener.status(skipped: false, succeeded: false), .failed)
    }

    func testSuiteFinishedWithoutStatusLetsReportPortalDeriveIt() throws {
        let endPoint = try FinishItemEndPoint(itemID: "item-1", status: nil, launchID: "run-1")
        XCTAssertNil(endPoint.parameters["status"])
        XCTAssertNil(endPoint.parameters["issue"])
        XCTAssertEqual(endPoint.parameters["launchUuid"] as? String, "run-1")
    }

    func testTestFinishKeepsItsStatusAndIssue() throws {
        let failed = try FinishItemEndPoint(itemID: "item-1", status: .failed, launchID: "run-1")
        XCTAssertEqual(failed.parameters["status"] as? String, "FAILED")
        XCTAssertEqual((failed.parameters["issue"] as? [String: String])?["issue_type"], "ti001")

        let skipped = try FinishItemEndPoint(itemID: "item-1", status: .skipped, launchID: "run-1")
        XCTAssertEqual(skipped.parameters["status"] as? String, "SKIPPED")
        XCTAssertEqual((skipped.parameters["issue"] as? [String: String])?["issue_type"], "NOT_ISSUE",
                       "a skip is not a defect to investigate")
    }

    func testLaunchFinishSendsNoStatus() {
        XCTAssertNil(FinishLaunchEndPoint(launchID: "run-1").parameters["status"],
                     "an explicit PASSED showed failed launches as passed")
    }
}

// MARK: - Request order and the end of the bundle

/// Each class's requests must reach ReportPortal in callback order. A test finished before it
/// was started has no id yet; a suite finished before its last test makes ReportPortal
/// force-finish that test with the suite's status.
final class ReportingOrderTests: XCTestCase {

    /// Not auto-discovered (no `test` prefix): only used as the subject of the callbacks.
    final class OrderingSample: XCTestCase {
        @objc func sample() {}
        @objc func other() {}
    }

    /// Records request order; a slow `startTest` makes a missing wait visible.
    private func makeListener(_ recorder: RecordingReportingService) -> RPListener {
        RPListener(injectedConfiguration: AgentConfiguration(
            reportPortalURL: URL(string: "https://example.invalid")!,
            projectName: "proj",
            launchName: "Launch",
            shouldSendReport: true,
            portalToken: "token",
            tags: [],
            launchMode: .default,
            testNameRules: []
        ), makeReportingService: { _ in recorder })
    }

    // Synchronous on purpose: XCTest runs it on the main thread, like the real callbacks.
    func testClassRequestsGoOutInCallbackOrderAndTheBundleEndWaitsForThem() {
        let recorder = RecordingReportingService()
        let listener = RPListener(injectedConfiguration: AgentConfiguration(
            reportPortalURL: URL(string: "https://example.invalid")!,
            projectName: "proj",
            launchName: "Launch",
            shouldSendReport: true,
            portalToken: "token",
            tags: [],
            launchMode: .default,
            testNameRules: []
        ), makeReportingService: { _ in recorder })

        let test = OrderingSample(selector: #selector(OrderingSample.sample))
        let suite = XCTestSuite(name: "OrderingSample")
        suite.addTest(test)

        let started = Date()
        listener.testBundleWillStart(Bundle(for: ReportingOrderTests.self))
        listener.testSuiteWillStart(suite)
        listener.testCaseWillStart(test)
        listener.testCaseDidFinish(test)
        listener.testSuiteDidFinish(suite)
        listener.testBundleDidFinish(Bundle(for: ReportingOrderTests.self))

        XCTAssertEqual(recorder.calls, ["startLaunch", "startSuite", "startTest", "finishTest", "finishSuite", "finalizeLaunch"])
        XCTAssertLessThan(Date().timeIntervalSince(started), 5,
                          "the bundle end waits for the pending requests, not a fixed delay")
    }

    func testAClassFilteredDownToNoTestsIsNotReported() {
        let recorder = RecordingReportingService()
        let listener = RPListener(injectedConfiguration: AgentConfiguration(
            reportPortalURL: URL(string: "https://example.invalid")!,
            projectName: "proj",
            launchName: "Launch",
            shouldSendReport: true,
            portalToken: "token",
            tags: [],
            launchMode: .default,
            testNameRules: []
        ), makeReportingService: { _ in recorder })

        let empty = XCTestSuite(name: "OrderingSample")
        listener.testBundleWillStart(Bundle(for: ReportingOrderTests.self))
        listener.testSuiteWillStart(empty)
        listener.testSuiteDidFinish(empty)
        listener.testBundleDidFinish(Bundle(for: ReportingOrderTests.self))

        XCTAssertEqual(recorder.calls, ["startLaunch", "finalizeLaunch"])
    }
}

// MARK: - Collapsing retries

final class CollapseRetriesTests: XCTestCase {

    func testSharedItemUUID_IsTheSameInEveryProcessOfTheRun() {
        let id = LaunchUUID.sharedItemUUID(launchUUID: "run-42-1", name: "ExampleUITests.LoginTests")
        XCTAssertEqual(id, LaunchUUID.sharedItemUUID(launchUUID: "run-42-1", name: "ExampleUITests.LoginTests"))
        XCTAssertNotEqual(id, LaunchUUID.sharedItemUUID(launchUUID: "run-42-2", name: "ExampleUITests.LoginTests"),
                          "another run must not join this run's suites")
        XCTAssertNotEqual(id, LaunchUUID.sharedItemUUID(launchUUID: "run-42-1", name: "ExampleUITests.SignupTests"))
        XCTAssertNotNil(UUID(uuidString: id))
        XCTAssertEqual(Array(id)[14], "5", "name-based SHA-1 UUID (version 5 layout)")
    }

    func testStartItem_SendsSharedUuidIdentityAndRetry() {
        let endPoint = StartItemEndPoint(itemName: "testLogin", parentID: "suite-1", launchID: "run-1", type: .step,
                                         attributes: [["key": "device", "value": "iPhone 15"]],
                                         uuid: "item-1", codeRef: "ExampleUITests.LoginTests.testLogin", retry: true)
        XCTAssertEqual(endPoint.relativePath, "item/suite-1")
        XCTAssertEqual(endPoint.parameters["uuid"] as? String, "item-1")
        XCTAssertEqual(endPoint.parameters["codeRef"] as? String, "ExampleUITests.LoginTests.testLogin")
        XCTAssertEqual(endPoint.parameters["testCaseId"] as? String, "ExampleUITests.LoginTests.testLogin")
        XCTAssertEqual(endPoint.parameters["retry"] as? Bool, true)
        XCTAssertEqual((endPoint.parameters["attributes"] as? [[String: String]])?.first?["value"], "iPhone 15")
    }

    func testStartItem_DefaultsSendNoneOfThem() {
        let endPoint = StartItemEndPoint(itemName: "testLogin", parentID: "suite-1", launchID: "run-1", type: .step)
        for key in ["uuid", "codeRef", "testCaseId", "retry"] {
            XCTAssertNil(endPoint.parameters[key], "\(key) must only be sent when set")
        }
    }

    func testCollapseRetries_IsOptIn() {
        XCTAssertFalse(RPListener.resolveCollapseRetries(from: Bundle(for: CollapseRetriesTests.self)))

        setenv("RP_COLLAPSE_RETRIES", "YES", 1)
        defer { unsetenv("RP_COLLAPSE_RETRIES") }
        XCTAssertTrue(RPListener.resolveCollapseRetries(from: nil))
    }
}

extension ReportingOrderTests {

    func testASuiteFinishesAfterAllItsTestsWhileTestsReportSideBySide() {
        let recorder = RecordingReportingService()
        let listener = makeListener(recorder)
        let first = OrderingSample(selector: #selector(OrderingSample.sample))
        let second = OrderingSample(selector: #selector(OrderingSample.other))
        let suite = XCTestSuite(name: "OrderingSample")
        suite.addTest(first)
        suite.addTest(second)

        let started = Date()
        listener.testBundleWillStart(Bundle(for: ReportingOrderTests.self))
        listener.testSuiteWillStart(suite)
        for test in [first, second] {
            listener.testCaseWillStart(test)
            listener.testCaseDidFinish(test)
        }
        listener.testSuiteDidFinish(suite)
        listener.testBundleDidFinish(Bundle(for: ReportingOrderTests.self))

        let calls = recorder.calls
        XCTAssertEqual(calls.filter { $0 == "finishTest" }.count, 2)
        XCTAssertEqual(Array(calls.suffix(2)), ["finishSuite", "finalizeLaunch"], "\(calls)")
        XCTAssertEqual(Array(calls.prefix(2)), ["startLaunch", "startSuite"], "\(calls)")
        // Each start sleeps 50 ms; the two tests overlap instead of queueing behind each other.
        XCTAssertLessThan(Date().timeIntervalSince(started), 5)
    }
}
