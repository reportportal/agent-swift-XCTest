//
//  ReportingService.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation
@preconcurrency import XCTest

/// Async/await API for ReportPortal communication (stateless)
/// Uses LaunchManager and OperationTracker for state management
public final class ReportingService: Sendable {

    // MARK: - Properties

    private let httpClient: HTTPClient
    private let configuration: AgentConfiguration
    private let launchManager: LaunchManager
    private let operationTracker: OperationTracker

    // MARK: - Initialization

    init(
        configuration: AgentConfiguration,
        httpClient: HTTPClient? = nil,
        launchManager: LaunchManager = LaunchManager.shared,
        operationTracker: OperationTracker = OperationTracker.shared
    ) {
        self.configuration = configuration
        self.launchManager = launchManager
        self.operationTracker = operationTracker

        if let client = httpClient {
            self.httpClient = client
        } else {
            let baseURL = configuration.reportPortalURL.appendingPathComponent(configuration.projectName)
            let authPlugin = AuthorizationPlugin(token: configuration.portalToken)
            self.httpClient = HTTPClient(baseURL: baseURL, plugins: [authPlugin])
        }
    }

    // MARK: - Launch Management

    /// Create new launch in ReportPortal
    /// - Parameters:
    ///   - name: Launch name (may include test plan name)
    ///   - tags: Tags from configuration
    ///   - attributes: Metadata (device info, OS version, etc.)
    /// - Returns: Launch ID (UUID string from ReportPortal)
    func startLaunch(name: String, tags: [String], attributes: [[String: String]]) async throws -> String {
        let endPoint = StartLaunchEndPoint(
            launchName: name,
            tags: tags,
            mode: configuration.launchMode,
            attributes: attributes
        )

        let result: FirstLaunch = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Launch created: \(result.id)")
        return result.id
    }

    /// Finish launch in ReportPortal
    /// - Parameters:
    ///   - launchID: Launch ID from LaunchManager
    ///   - status: Aggregated status from LaunchManager
    func finalizeLaunch(launchID: String, status: TestStatus) async throws {
        let endPoint = FinishLaunchEndPoint(launchID: launchID, status: status)

        let _: LaunchFinish = try await httpClient.callEndPoint(endPoint)

        // Mark as finalized in LaunchManager
        await launchManager.markFinalized()

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
            // This is a test class suite (child of root suite)
            // It should be .suite, not .test (test classes are suites, not individual tests)
            endPoint = StartItemEndPoint(
                itemName: operation.suiteName,
                parentID: rootSuiteID,
                launchID: launchID,
                type: .suite  // Fixed: was .test, should be .suite
            )
        } else {
            // This is a root suite (bundle)
            endPoint = StartItemEndPoint(
                itemName: operation.suiteName,
                launchID: launchID,
                type: .suite
            )
        }

        let result: Item = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Suite started: \(result.id)", correlationID: operation.correlationID)
        return result.id
    }

    /// Finish suite item in ReportPortal
    /// - Parameter operation: SuiteOperation with suite ID and final status
    func finishSuite(operation: SuiteOperation) async throws {
        guard let launchID = await launchManager.getLaunchID() else {
            throw ReportingServiceError.launchIdNotFound
        }

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
            type: .step
        )

        let result: Item = try await httpClient.callEndPoint(endPoint)

        Logger.shared.info("Test started: \(result.id)", correlationID: operation.correlationID)
        return result.id
    }

    /// Finish test item in ReportPortal
    /// - Parameter operation: TestOperation with test ID and final status
    func finishTest(operation: TestOperation) async throws {
        guard let launchID = await launchManager.getLaunchID() else {
            throw ReportingServiceError.launchIdNotFound
        }

        let endPoint = try FinishItemEndPoint(
            itemID: operation.testID,
            status: operation.status,
            launchID: launchID
        )

        let _: Finish = try await httpClient.callEndPoint(endPoint)

        // Update aggregated status in LaunchManager
        await launchManager.updateStatus(operation.status)

        Logger.shared.info("Test finished: \(operation.testID) with status: \(operation.status.rawValue)", correlationID: operation.correlationID)
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
    func postAttachments(
        attachments: [XCTAttachment],
        itemID: String,
        launchID: String,
        correlationID: UUID? = nil
    ) async throws {
        guard !attachments.isEmpty else {
            Logger.shared.debug("No attachments to upload", correlationID: correlationID)
            return
        }

        var fileAttachments: [FileAttachment] = []

        // Extract attachment data
        for (index, attachment) in attachments.enumerated() {
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

            // Extract data from XCTAttachment
            guard let fileWrapper = attachment.value(forKey: "fileWrapper") as? FileWrapper,
                  let data = fileWrapper.regularFileContents else {
                Logger.shared.warning("Could not extract data from attachment: \(attachment.name ?? "unknown")", correlationID: correlationID)
                continue
            }

            // Create FileAttachment and add to array
            let fileAttachment = FileAttachment(
                data: data,
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
