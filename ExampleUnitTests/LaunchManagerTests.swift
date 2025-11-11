//
//  LaunchManagerTests.swift
//  ExampleUnitTests
//
//  Created for ReportPortal Agent v4.0
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest
@testable import ReportPortalAgent

/// Unit tests for LaunchManager actor
/// Tests thread-safe launch coordination, reference counting, and status aggregation
final class LaunchManagerTests: XCTestCase {

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        // Reset LaunchManager state before each test
        await LaunchManager.shared.reset()
    }

    // MARK: - Launch ID Tests

    func testCreateLaunch_CreatesLaunchSuccessfully() async throws {
        // Given: A launch creation task
        let task = Task<String, Error> {
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "launch-123"
        }

        // When: Create launch
        let launchID = try await LaunchManager.shared.createLaunch(launchTask: task)

        // Then: Should return launch ID
        XCTAssertEqual(launchID, "launch-123", "Should create and return launch ID")

        // Verify launch ID is stored
        let storedID = await LaunchManager.shared.getLaunchID()
        XCTAssertEqual(storedID, "launch-123", "Launch ID should be stored")
    }

    func testCreateLaunch_ReturnsExistingID() async throws {
        // Given: Launch already created
        let task1 = Task<String, Error> { "launch-existing" }
        _ = try await LaunchManager.shared.createLaunch(launchTask: task1)

        // When: Try to create launch again
        let task2 = Task<String, Error> {
            return "launch-should-not-be-used"
        }

        let launchID = try await LaunchManager.shared.createLaunch(launchTask: task2)

        // Then: Should return existing ID
        XCTAssertEqual(launchID, "launch-existing", "Should return existing launch ID")
    }

    func testGetLaunchID_ReturnsNilWhenNotSet() async {
        // Given: No launch created

        // When: Get launch ID
        let launchID = await LaunchManager.shared.getLaunchID()

        // Then: Should return nil
        XCTAssertNil(launchID, "Should return nil when launch not created")
    }

    func testGetLaunchID_ReturnsIDWhenSet() async throws {
        // Given: Launch created
        let task = Task<String, Error> { "launch-789" }
        _ = try await LaunchManager.shared.createLaunch(launchTask: task)

        // When: Get launch ID
        let launchID = await LaunchManager.shared.getLaunchID()

        // Then: Should return launch ID
        XCTAssertEqual(launchID, "launch-789", "Should return created launch ID")
    }

    func testCreateLaunch_RetryAfterFailure() async throws {
        // Given: First task fails
        let task1 = Task<String, Error> {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        }

        do {
            _ = try await LaunchManager.shared.createLaunch(launchTask: task1)
            XCTFail("Should throw error")
        } catch {
            // Expected failure
        }

        // When: Second task succeeds
        let task2 = Task<String, Error> { "launch-retry-success" }
        let launchID = try await LaunchManager.shared.createLaunch(launchTask: task2)

        // Then: Should succeed with new launch ID
        XCTAssertEqual(launchID, "launch-retry-success", "Should retry after failure")
    }

    // MARK: - Status Aggregation Tests

    func testUpdateStatus_PassedRemainsPassed() async {
        // Given: Status is passed

        // When: Update with passed
        await LaunchManager.shared.updateStatus(.passed)

        // Then: Status should be passed
        let status = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(status, .passed, "Status should remain passed")
    }

    func testUpdateStatus_FailedOverridesPassed() async {
        // Given: Status is passed
        await LaunchManager.shared.updateStatus(.passed)

        // When: Update with failed
        await LaunchManager.shared.updateStatus(.failed)

        // Then: Status should be failed
        let status = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(status, .failed, "Failed should override passed")
    }

    func testUpdateStatus_SkippedOverridesPassed() async {
        // Given: Status is passed
        await LaunchManager.shared.updateStatus(.passed)

        // When: Update with skipped
        await LaunchManager.shared.updateStatus(.skipped)

        // Then: Status should be skipped
        let status = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(status, .skipped, "Skipped should override passed")
    }

    func testUpdateStatus_FailedRemainsFailedOverSkipped() async {
        // Given: Status is failed
        await LaunchManager.shared.updateStatus(.failed)

        // When: Update with skipped
        await LaunchManager.shared.updateStatus(.skipped)

        // Then: Status should remain failed (higher severity)
        let status = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(status, .failed, "Failed should remain over skipped")
    }

    func testUpdateStatus_ConcurrentUpdates() async {
        // Given: Multiple concurrent status updates
        let statuses: [TestStatus] = [.passed, .failed, .skipped, .passed, .failed]

        // When: Update status concurrently
        await withTaskGroup(of: Void.self) { group in
            for status in statuses {
                group.addTask {
                    await LaunchManager.shared.updateStatus(status)
                }
            }
        }

        // Then: Should aggregate to worst status (failed)
        let finalStatus = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(finalStatus, .failed, "Should aggregate to worst status (failed)")
    }

    // MARK: - Finalization Tests

    func testMarkFinalized() async {
        // Given: Launch not finalized
        let isFinalized = await LaunchManager.shared.isLaunchFinalized()
        XCTAssertFalse(isFinalized, "Should not be finalized initially")

        // When: Mark as finalized
        await LaunchManager.shared.markFinalized()

        // Then: Should be finalized
        let newIsFinalized = await LaunchManager.shared.isLaunchFinalized()
        XCTAssertTrue(newIsFinalized, "Should be finalized after marking")
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllState() async throws {
        // Given: LaunchManager with state
        let task = Task<String, Error> { "launch-reset" }
        _ = try await LaunchManager.shared.createLaunch(launchTask: task)
        await LaunchManager.shared.updateStatus(.failed)
        await LaunchManager.shared.markFinalized()

        // When: Reset
        await LaunchManager.shared.reset()

        // Then: All state should be cleared
        let launchID = await LaunchManager.shared.getLaunchID()
        let status = await LaunchManager.shared.getAggregatedStatus()
        let isFinalized = await LaunchManager.shared.isLaunchFinalized()

        XCTAssertNil(launchID, "Launch ID should be nil")
        XCTAssertEqual(status, .passed, "Status should be reset to passed")
        XCTAssertFalse(isFinalized, "Finalized flag should be reset")
    }

    // MARK: - Integration Tests

    func testSimpleLaunchLifecycle() async throws {
        // Given: Single test bundle

        // When: Create launch
        let task = Task<String, Error> { "launch-lifecycle" }
        let launchID = try await LaunchManager.shared.createLaunch(launchTask: task)
        XCTAssertEqual(launchID, "launch-lifecycle")

        // Update statuses from tests
        await LaunchManager.shared.updateStatus(.passed)
        await LaunchManager.shared.updateStatus(.failed)
        await LaunchManager.shared.updateStatus(.passed)

        // Check aggregated status
        let finalStatus = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(finalStatus, .failed, "Should aggregate to failed")

        // Mark finalized
        await LaunchManager.shared.markFinalized()
        let isFinalized = await LaunchManager.shared.isLaunchFinalized()
        XCTAssertTrue(isFinalized)
    }
}
