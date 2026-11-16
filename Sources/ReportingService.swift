//  Created by Ruslan Popesku on 10/22/25.
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
@preconcurrency import XCTest

extension HTTPClientError {
    /// A 409 Conflict from the finish-launch endpoint means the launch was already
    /// finished (idempotent). It is the ONLY non-fatal finalize error; every other HTTP
    /// status and every non-HTTP error (network, decoding) is fatal and must propagate.
    var isLaunchAlreadyFinished: Bool {
        if case .httpError(let statusCode, _) = self, statusCode == 409 {
            return true
        }
        return false
    }
}

/// Async/await API for ReportPortal communication (stateless)
public final class ReportingService: Sendable {

    // MARK: - Properties

    private let httpClient: HTTPClient
    /// Separate client pinned to the **v1** API. ReportPortal's *read* endpoints
    /// (`GET launch/uuid/{uuid}`, `GET item/…`) only exist under `/api/v1`, while `httpClient`
    /// is pinned to `/api/v2` (start/finish/merge).
    private let httpClientV1: HTTPClient
    private let configuration: AgentConfiguration

    // MARK: - Initialization

    init(configuration: AgentConfiguration) {
        self.configuration = configuration
        
        // Build V2 API base URL: https://reportportal.epam.com/api/v2/{project}
        // User provides: https://reportportal.epam.com
        let baseURL = configuration.reportPortalURL
            .appendingPathComponent("api")
            .appendingPathComponent("v2")
            .appendingPathComponent(configuration.projectName)
        // V1 base — for launch read/update (those endpoints don't exist under v2).
        let baseURLV1 = configuration.reportPortalURL
            .appendingPathComponent("api")
            .appendingPathComponent("v1")
            .appendingPathComponent(configuration.projectName)

        let authPlugin = AuthorizationPlugin(token: configuration.portalToken)
        self.httpClient = HTTPClient(baseURL: baseURL, plugins: [authPlugin])
        self.httpClientV1 = HTTPClient(baseURL: baseURLV1, plugins: [authPlugin])
    }

    // MARK: - Launch Management

    /// Create new launch in ReportPortal using V2 API with mandatory UUID
    /// - Parameters:
    ///   - name: Launch name (may include test plan name)
    ///   - tags: Tags from configuration
    ///   - attributes: Metadata (device info, OS version, etc.)
    ///   - uuid: **REQUIRED** Custom UUID for idempotent launch creation (V2 API)
    /// - Returns: Launch ID (UUID string from ReportPortal)
    ///
    /// ## V2 API Behavior:
    /// - **Idempotent**: Multiple calls with same UUID report into the same launch. Reporting is
    ///   asynchronous: a duplicate start gets a success response and is dropped server-side.
    /// - **Parallel-safe**: All workers can call simultaneously with same UUID
    func startLaunch(name: String, tags: [String], attributes: [[String: String]], uuid: String) async throws -> String {
        let endPoint = StartLaunchEndPoint(
            launchName: name,
            tags: tags,
            mode: configuration.launchMode,
            attributes: attributes,
            uuid: uuid
        )

        let result: FirstLaunch = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Launch created via V2 API: \(result.id)")
        return result.id
    }

    /// Finish launch in ReportPortal. No status is sent: ReportPortal calculates it from the tests.
    /// - Parameter launchID: Launch ID from LaunchUUID.value
    func finalizeLaunch(launchID: String) async throws {
        do {
            let endPoint = FinishLaunchEndPoint(launchID: launchID)
            let _: LaunchFinish = try await httpClient.callEndPoint(endPoint)
            Logger.shared.info("Launch finalized: \(launchID)")
        } catch let error as HTTPClientError {
            if error.isLaunchAlreadyFinished {
                Logger.shared.warning("⚠️ Launch finalization returned 409 — launch already finished (idempotent, non-fatal)")
                return
            }
            throw error
        }
    }

    /// Start time of a launch as ReportPortal stored it. Throws while the launch does not exist
    /// yet — v2 reporting is asynchronous, so a just-started launch can lag behind.
    func launchStartTime(uuid: String) async throws -> Date? {
        let launch: Launch = try await httpClientV1.callEndPoint(GetLaunchByUuidEndPoint(uuid: uuid))
        return launch.startTime?.date
    }

    // MARK: - Suite Management

    /// Create suite item in ReportPortal
    /// - Parameters:
    ///   - operation: SuiteOperation with metadata
    ///   - launchID: Parent launch ID
    /// - Returns: Suite item ID (UUID string)
    func startSuite(operation: SuiteOperation, launchID: String) async throws -> String {
        if let sharedUUID = operation.sharedUUID {
            return try await joinSharedSuite(operation: operation, uuid: sharedUUID, launchID: launchID)
        }

        // A test class is a top-level item of the launch.
        let endPoint = StartItemEndPoint(
            itemName: operation.suiteName,
            launchID: launchID,
            type: .suite,
            codeRef: operation.codeRef
        )

        let result: Item = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Suite started: \(result.id)", correlationID: operation.correlationID)
        return result.id
    }

    /// A suite shared by every process of the launch: reuse it when another process already
    /// created it, otherwise create it under the shared uuid (a concurrent duplicate is dropped by
    /// the server). Then read back the start time the server stored and never stamp a child
    /// earlier: ReportPortal drops a child that starts before its parent, silently on the async
    /// API, so a device whose clock lags the suite's creator would lose its tests.
    private func joinSharedSuite(operation: SuiteOperation, uuid: String, launchID: String) async throws -> String {
        if let start = try? await item(uuid: uuid).startTime?.date {
            TimeHelper.clamp(notBefore: start)
            Logger.shared.info("🔗 Joined shared suite '\(operation.suiteName)' (\(uuid))", correlationID: operation.correlationID)
            return uuid
        }

        let endPoint = StartItemEndPoint(
            itemName: operation.suiteName,
            launchID: launchID,
            type: .suite,
            uuid: uuid,
            codeRef: operation.codeRef
        )
        let _: Item = try await httpClient.callEndPoint(endPoint)

        if await TimeHelper.clamp(toStoredStart: { try await self.item(uuid: uuid).startTime?.date }) != nil {
            Logger.shared.info("🔗 Created shared suite '\(operation.suiteName)' (\(uuid))", correlationID: operation.correlationID)
        } else {
            Logger.shared.warning("⚠️ Could not read shared suite '\(operation.suiteName)' back; a lagging device clock may lose its tests", correlationID: operation.correlationID)
        }
        return uuid
    }

    /// An item as ReportPortal stored it. Throws while it does not exist.
    private func item(uuid: String) async throws -> ItemResource {
        try await httpClientV1.callEndPoint(GetItemByUuidEndPoint(uuid: uuid))
    }

    /// Uuids of a suite's tests that ReportPortal still shows as running, in any process.
    func runningTests(inSuite uuid: String) async throws -> [String] {
        let suite = try await item(uuid: uuid)
        guard let id = suite.id, let launchID = suite.launchId else {
            throw HTTPClientError.decodingError("Item \(uuid) has no id or launchId")
        }
        let running: ItemPage = try await httpClientV1.callEndPoint(
            GetRunningChildrenEndPoint(parentID: id, launchID: launchID)
        )
        return try running.allUUIDs()
    }

    /// Finish suite item in ReportPortal
    /// - Parameter operation: SuiteOperation with suite ID and final status
    func finishSuite(operation: SuiteOperation) async throws {
        let launchID = LaunchUUID.value

        // Without an explicit status ReportPortal derives the suite's from its tests.
        let endPoint = try FinishItemEndPoint(
            itemID: operation.suiteID,
            status: operation.status,
            launchID: launchID
        )

        let _: Finish = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Suite finished: \(operation.suiteID)", correlationID: operation.correlationID)
    }

    // MARK: - Test Management

    /// Create test item in ReportPortal
    /// - Parameters:
    ///   - operation: TestOperation with metadata
    ///   - launchID: Parent launch ID
    /// - Returns: Test item ID (UUID string)
    func startTest(operation: TestOperation, launchID: String) async throws -> String {
        let endPoint = StartItemEndPoint(
            itemName: operation.testName,
            parentID: operation.suiteID,
            launchID: launchID,
            type: .step,  // Individual test method = type .step
            attributes: operation.attributes,
            codeRef: operation.codeRef,
            retry: operation.retry
        )

        let result: Item = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Test started: \(result.id)", correlationID: operation.correlationID)
        return result.id
    }

    /// Finish test item in ReportPortal
    /// - Parameter operation: TestOperation with test ID and final status
    func finishTest(operation: TestOperation) async throws {
        guard let status = operation.status else {
            preconditionFailure("Test status should not be nil when finishing test")
        }
        
        let launchID = LaunchUUID.value

        let endPoint = try FinishItemEndPoint(
            itemID: operation.testID,
            status: status,
            launchID: launchID
        )

        let _: Finish = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Test finished: \(operation.testID) with status: \(status.rawValue)", correlationID: operation.correlationID)
    }

    // MARK: - Logging & Attachments

    /// Send log entry to ReportPortal
    /// - Parameters:
    ///   - message: Log message text
    ///   - level: Log level (info, warn, error, etc.)
    ///   - itemID: Test or suite item ID
    ///   - launchID: Launch ID
    ///   - correlationID: Optional correlation ID for tracing
    func postLog(
        message: String,
        level: String = "info",
        itemID: String,
        launchID: String,
        correlationID: UUID? = nil
    ) async throws {
        let endPoint = PostLogEndPoint(
            itemUuid: itemID,
            launchUuid: launchID,
            level: level,
            message: message,
            attachments: []
        )

        let _: LogResponse = try await httpClient.callEndPoint(endPoint)

        Logger.shared.debug("Log posted to item: \(itemID)", correlationID: correlationID)
    }

    /// Post a failure screenshot to a test item
    func postScreenshot(
        screenshotData: Data,
        filename: String,
        itemID: String,
        launchID: String,
        correlationID: UUID? = nil
    ) async throws {
        let fileAttachment = FileAttachment(
            data: screenshotData,
            filename: filename,
            mimeType: "image/png",
            fieldName: "binary_part"
        )

        let endPoint = PostLogEndPoint(
            itemUuid: itemID,
            launchUuid: launchID,
            level: "info",
            message: "Failure screenshot",
            attachments: [fileAttachment]
        )

        let _: LogResponse = try await httpClient.callEndPoint(endPoint)

        Logger.shared.debug("Posted screenshot: \(filename)", correlationID: correlationID)
    }
}

// MARK: - Read endpoints (v1)
//
// They live here (rather than in Sources/EndPoints/) so both SPM and the Xcode project compile
// them without a project-file change.

/// `GET launch/uuid/{uuid}` — read a launch, e.g. the start time ReportPortal stored.
struct GetLaunchByUuidEndPoint: EndPoint {
    let method: HTTPMethod = .get
    let relativePath: String

    init(uuid: String) {
        relativePath = "launch/uuid/\(uuid)"
    }
}

/// `GET item/uuid/{uuid}` — read an item (v1 only), e.g. to join a suite another process created.
struct GetItemByUuidEndPoint: EndPoint {
    let method: HTTPMethod = .get
    let relativePath: String

    init(uuid: String) {
        relativePath = "item/uuid/\(uuid)"
    }
}

/// `GET item?filter…` — the children of an item that are still running (v1 only).
struct GetRunningChildrenEndPoint: EndPoint {
    let method: HTTPMethod = .get
    let relativePath = "item"
    let encoding: ParameterEncoding = .url
    let parameters: [String: Any]

    init(parentID: Int, launchID: Int) {
        parameters = [
            "filter.eq.launchId": launchID,
            "filter.eq.parentId": parentID,
            "filter.eq.status": "IN_PROGRESS",
            "page.size": 100
        ]
    }
}

/// The part of ReportPortal's item resource the agent reads.
struct ItemResource: Decodable {
    let id: Int?
    let uuid: String?
    let launchId: Int?
    let startTime: ServerTime?
}

/// A page of items, as `GET item` returns it.
struct ItemPage: Decodable {
    let content: [ItemResource]
    let page: Page?

    /// The items' uuids. Throws when the server holds more than this page, so none is missed.
    func allUUIDs() throws -> [String] {
        guard (page?.totalElements ?? content.count) <= content.count else {
            throw HTTPClientError.decodingError("\(content.count) of \(page?.totalElements ?? 0) items fit in one page")
        }
        return content.compactMap { $0.uuid }
    }
}

// MARK: - ReportingServiceProtocol (ordering test seam)
//
// `RPListener` depends on this protocol rather than the concrete `ReportingService`, so unit
// tests can inject a recording double and assert the ORDER of ReportPortal calls — in
// particular that the launch is created BEFORE any suite/test item is sent (the "attribute-less
// orphan" bug). This is a pure abstraction: `ReportingService` already implements every method,
// so production behavior is unchanged. Kept here (not a new file) so the Xcode project compiles
// it without a project-file change.
protocol ReportingServiceProtocol: Sendable {
    func startLaunch(name: String, tags: [String], attributes: [[String: String]], uuid: String) async throws -> String
    func launchStartTime(uuid: String) async throws -> Date?
    func startSuite(operation: SuiteOperation, launchID: String) async throws -> String
    func finishSuite(operation: SuiteOperation) async throws
    func runningTests(inSuite uuid: String) async throws -> [String]
    func startTest(operation: TestOperation, launchID: String) async throws -> String
    func finishTest(operation: TestOperation) async throws
    func postLog(message: String, level: String, itemID: String, launchID: String, correlationID: UUID?) async throws
    func postScreenshot(screenshotData: Data, filename: String, itemID: String, launchID: String, correlationID: UUID?) async throws
    func finalizeLaunch(launchID: String) async throws
}

extension ReportingService: ReportingServiceProtocol {}
