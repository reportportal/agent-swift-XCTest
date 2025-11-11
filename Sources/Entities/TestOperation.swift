//
//  TestOperation.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation
@preconcurrency import XCTest

/// Thread-safe value type representing an XCTAttachment's data
/// Extracts immutable data from XCTAttachment for safe cross-actor usage
struct AttachmentPayload: Sendable {
    /// Attachment name (e.g., "Screenshot", "Error Log")
    let name: String?
    
    /// Uniform Type Identifier (e.g., "public.png", "public.plain-text")
    let uniformTypeIdentifier: String
    
    /// XCTAttachment lifetime setting
    let lifetime: XCTAttachment.Lifetime
    
    /// Raw attachment data (PNG bytes, text content, etc.)
    let data: Data?
    
    /// Initialize from XCTAttachment (async to handle screenshot extraction)
    @MainActor
    init(from attachment: XCTAttachment) async {
        self.name = attachment.name
        self.uniformTypeIdentifier = attachment.uniformTypeIdentifier
        self.lifetime = attachment.lifetime
        
        // Extract data - for screenshots, get PNG representation
        var extractedData: Data? = nil
        
        #if canImport(UIKit)
        // Try to extract screenshot data
        if uniformTypeIdentifier.contains("image") {
            if let screenshot = attachment.value(forKey: "screenshot") as? XCUIScreenshot {
                extractedData = screenshot.pngRepresentation
            } else if let image = attachment.value(forKey: "image") as? XCUIScreenshot {
                extractedData = image.pngRepresentation
            }
        }
        #endif
        
        // If no screenshot data, try general data access
        if extractedData == nil {
            // XCTAttachment doesn't expose data directly in all cases
            // We'll handle data extraction in ReportingService if needed
            extractedData = nil
        }
        
        self.data = extractedData
    }
    
    /// Convert back to XCTAttachment for ReportPortal upload
    func toXCTAttachment() -> XCTAttachment {
        if let data = data {
            let attachment = XCTAttachment(data: data, uniformTypeIdentifier: uniformTypeIdentifier)
            attachment.name = name
            attachment.lifetime = lifetime
            return attachment
        } else {
            // Fallback for attachments without data
            let attachment = XCTAttachment(string: name ?? "Unknown")
            attachment.lifetime = lifetime
            return attachment
        }
    }
}

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

    /// Screenshots, logs collected during test (Sendable-safe payloads)
    var attachments: [AttachmentPayload]

    /// Initialize a new test operation
    init(
        correlationID: UUID = UUID(),
        testID: String,
        suiteID: String,
        testName: String,
        className: String,
        status: TestStatus = .inProgress,
        startTime: Date = Date(),
        metadata: [String: String] = [:],
        attachments: [AttachmentPayload] = []
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
