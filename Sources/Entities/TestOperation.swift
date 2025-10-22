//
//  TestOperation.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation
@preconcurrency import XCTest

/// Represents an isolated execution context for a single test case.
/// Immutable value type ensures no shared state between concurrent tests.
struct TestOperation: Sendable {
    /// Unique identifier for tracing this test's lifecycle across logs
    let correlationID: UUID

    /// ReportPortal item ID for this test case (mutable to set after API call)
    var testID: String

    /// Parent suite ID (for hierarchy)
    let suiteID: String

    /// XCTest test method name (e.g., "testExample")
    let testName: String

    /// XCTest class name (e.g., "MyTestCase")
    let className: String

    /// Current status (.passed, .failed, .skipped, etc.)
    var status: TestStatus

    /// Test start timestamp
    let startTime: Date

    /// Device info, test plan name, tags, etc.
    var metadata: [String: String]

    /// Screenshots, logs collected during test
    var attachments: [XCTAttachment]

    /// Initialize a new test operation
    init(
        correlationID: UUID = UUID(),
        testID: String,
        suiteID: String,
        testName: String,
        className: String,
        status: TestStatus = .passed,
        startTime: Date = Date(),
        metadata: [String: String] = [:],
        attachments: [XCTAttachment] = []
    ) {
        self.correlationID = correlationID
        self.testID = testID
        self.suiteID = suiteID
        self.testName = testName
        self.className = className
        self.status = status
        self.startTime = startTime
        self.metadata = metadata
        self.attachments = attachments
    }
}
