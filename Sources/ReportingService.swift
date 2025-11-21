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

/// Async/await API for ReportPortal communication (stateless)
/// Uses LaunchManager and OperationTracker for state management
public final class ReportingService: Sendable {

    // MARK: - Properties

    private let httpClient: HTTPClient
    private let configuration: AgentConfiguration
    private let operationTracker: OperationTracker

    // MARK: - Initialization

    init(
        configuration: AgentConfiguration,
        httpClient: HTTPClient? = nil,
        operationTracker: OperationTracker = OperationTracker.shared
    ) {
        self.configuration = configuration
        self.operationTracker = operationTracker
        
        // Build V2 API base URL: https://reportportal.epam.com/api/v2/{project}
        // User provides: https://reportportal.epam.com
        let baseURL = configuration.reportPortalURL
            .appendingPathComponent("api")
            .appendingPathComponent("v2")
            .appendingPathComponent(configuration.projectName)

        if let client = httpClient {
            self.httpClient = client
        } else {
            let authPlugin = AuthorizationPlugin(token: configuration.portalToken)
            self.httpClient = HTTPClient(baseURL: baseURL, plugins: [authPlugin])
        }
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
    /// - **Idempotent**: Multiple calls with same UUID return same launch
    /// - **409 Conflict**: Expected when launch already exists (caller should handle gracefully)
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

    /// Finish launch in ReportPortal
    /// - Parameters:
    ///   - launchID: Launch ID from LaunchManager
    ///   - status: Status to send (ReportPortal will calculate actual status from tests)
    func finalizeLaunch(launchID: String, status: TestStatus) async throws {
        let endPoint = FinishLaunchEndPoint(launchID: launchID, status: status)

        let _: LaunchFinish = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Launch finalized: \(launchID) with status: \(status.rawValue)")
    }

    // MARK: - Suite Management

    /// Create suite item in ReportPortal
    /// - Parameters:
    ///   - operation: SuiteOperation with metadata
    ///   - launchID: Parent launch ID
    /// - Returns: Suite item ID (UUID string)
    func startSuite(operation: SuiteOperation, launchID: String) async throws -> String {
        let endPoint: StartItemEndPoint

        if let rootSuiteID = operation.rootSuiteID {
            // This is a child suite (test class) - parent is root suite
            // Use .test for test classes (not .suite)
            endPoint = StartItemEndPoint(
                itemName: operation.suiteName,
                parentID: rootSuiteID,
                launchID: launchID,
                type: .test  // Test class = type .test
            )
        } else {
            // This is a root suite (bundle)
            endPoint = StartItemEndPoint(
                itemName: operation.suiteName,
                launchID: launchID,
                type: .suite  // Bundle = type .suite
            )
        }

        let result: Item = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Suite started: \(result.id)", correlationID: operation.correlationID)
        return result.id
    }

    /// Finish suite item in ReportPortal
    /// - Parameter operation: SuiteOperation with suite ID and final status
    func finishSuite(operation: SuiteOperation) async throws {
        let launchID = LaunchManager.shared.launchID

        // Use suite status if available, otherwise default to passed
        let status = operation.status ?? .passed

        let endPoint = try FinishItemEndPoint(
            itemID: operation.suiteID,
            status: status,
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
            type: .step  // Individual test method = type .step
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
        
        let launchID = LaunchManager.shared.launchID

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

    /// Post attachments to ReportPortal (async, non-blocking)
    /// - Parameters:
    ///   - attachments: Array of XCTAttachment from test
    ///   - itemID: Test item ID to attach to
    ///   - launchID: Launch ID
    ///   - correlationID: Optional correlation ID for tracing
    /// Post screenshot directly to ReportPortal (simpler than postAttachments)
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

    func postAttachments(
        attachments: [AttachmentPayload],
        itemID: String,
        launchID: String,
        correlationID: UUID? = nil
    ) async throws {
        guard !attachments.isEmpty else {
            Logger.shared.debug("No attachments to upload", correlationID: correlationID)
            return
        }

        var fileAttachments: [FileAttachment] = []

        // Convert AttachmentPayload to FileAttachment
        for (index, attachment) in attachments.enumerated() {
            // Skip attachments without data
            guard let attachmentData = attachment.data else {
                Logger.shared.warning("Attachment has no data: \(attachment.name ?? "unknown"), UTI: \(attachment.uniformTypeIdentifier)", correlationID: correlationID)
                continue
            }
            
            // Generate safe filename from attachment name or use timestamp
            let timestamp = String(Int64(Date().timeIntervalSince1970 * 1000))
            let baseName = attachment.name ?? "attachment_\(index)"
            let sanitizedName = baseName.replacingOccurrences(of: " ", with: "_")

            // Determine MIME type and extension based on uniformTypeIdentifier
            let uti = attachment.uniformTypeIdentifier
            let fileExtension: String
            let mimeType: String

            // Common attachment types
            if uti.contains("image") || uti.contains("png") {
                fileExtension = "png"
                mimeType = "image/png"
            } else if uti.contains("jpeg") || uti.contains("jpg") {
                fileExtension = "jpg"
                mimeType = "image/jpeg"
            } else if uti.contains("text") {
                fileExtension = "txt"
                mimeType = "text/plain"
            } else if uti.contains("json") {
                fileExtension = "json"
                mimeType = "application/json"
            } else if uti.contains("xml") {
                fileExtension = "xml"
                mimeType = "application/xml"
            } else {
                fileExtension = "bin"
                mimeType = "application/octet-stream"
            }

            // Build filename with timestamp and extension
            let filename = "\(sanitizedName)_\(timestamp).\(fileExtension)"

            // Create FileAttachment and add to array
            let fileAttachment = FileAttachment(
                data: attachmentData,
                filename: filename,
                mimeType: mimeType,
                fieldName: "binary_part"
            )
            fileAttachments.append(fileAttachment)
        }

        guard !fileAttachments.isEmpty else {
            Logger.shared.debug("No processable attachments after extraction", correlationID: correlationID)
            return
        }

        // Upload all attachments in a single API call
        let endPoint = PostLogEndPoint(
            itemUuid: itemID,
            launchUuid: launchID,
            level: "info",
            message: "Test attachments",
            attachments: fileAttachments
        )

        let _: LogResponse = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Uploaded \(fileAttachments.count) attachments to item: \(itemID)", correlationID: correlationID)
    }
}
