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

    // MARK: - Bundle Count Tests

    func testIncrementBundleCount() async {
        // Given: Fresh LaunchManager
        let initialCount = await LaunchManager.shared.getActiveBundleCount()
        XCTAssertEqual(initialCount, 0, "Initial count should be 0")

        // When: Increment bundle count
        await LaunchManager.shared.incrementBundleCount()

        // Then: Count should be 1
        let newCount = await LaunchManager.shared.getActiveBundleCount()
        XCTAssertEqual(newCount, 1, "Count should increment to 1")
    }

    func testDecrementBundleCount() async {
        // Given: Bundle count of 2
        await LaunchManager.shared.incrementBundleCount()
        await LaunchManager.shared.incrementBundleCount()

        // When: Decrement once
        let shouldFinalize = await LaunchManager.shared.decrementBundleCount()

        // Then: Should not finalize yet (count = 1)
        XCTAssertFalse(shouldFinalize, "Should not finalize with active bundles remaining")
        let count = await LaunchManager.shared.getActiveBundleCount()
        XCTAssertEqual(count, 1, "Count should decrement to 1")
    }

    func testDecrementToZeroReturnsTrue() async {
        // Given: Bundle count of 1
        await LaunchManager.shared.incrementBundleCount()

        // When: Decrement to zero
        let shouldFinalize = await LaunchManager.shared.decrementBundleCount()

        // Then: Should finalize (count = 0)
        XCTAssertTrue(shouldFinalize, "Should finalize when count reaches zero")
        let count = await LaunchManager.shared.getActiveBundleCount()
        XCTAssertEqual(count, 0, "Count should be 0")
    }

    func testConcurrentBundleCountIncrement() async {
        // Given: Multiple concurrent bundle starts
        let bundleCount = 10

        // When: Multiple bundles increment concurrently
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<bundleCount {
                group.addTask {
                    await LaunchManager.shared.incrementBundleCount()
                }
            }
        }

        // Then: Count should be exactly bundleCount (no race conditions)
        let finalCount = await LaunchManager.shared.getActiveBundleCount()
        XCTAssertEqual(finalCount, bundleCount, "Concurrent increments should be atomic")
    }

    // MARK: - Launch ID Tests

    func testGetOrAwaitLaunchID_CreatesLaunchOnce() async throws {
        // Given: Two concurrent launch creation tasks
        var launchCreationCount = 0
        let creationCountLock = NSLock()

        let task1 = Task<String, Error> {
            creationCountLock.lock()
            launchCreationCount += 1
            creationCountLock.unlock()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "launch-123"
        }

        let task2 = Task<String, Error> {
            creationCountLock.lock()
            launchCreationCount += 1
            creationCountLock.unlock()
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            return "launch-456"
        }

        // When: Both tasks try to get launch ID
        async let launchID1: String = LaunchManager.shared.getOrAwaitLaunchID(launchTask: task1)
        async let launchID2: String = LaunchManager.shared.getOrAwaitLaunchID(launchTask: task2)

        let (id1, id2) = try await (launchID1, launchID2)

        // Then: Both should get the same launch ID (first task wins)
        XCTAssertEqual(id1, id2, "Both bundles should get same launch ID")
        XCTAssertEqual(id1, "launch-123", "Should use first task's result")

        // Only one launch should have been created
        creationCountLock.lock()
        XCTAssertEqual(launchCreationCount, 1, "Launch should only be created once")
        creationCountLock.unlock()
    }

    func testGetOrAwaitLaunchID_ReturnsExistingID() async throws {
        // Given: Launch already created
        let task1 = Task<String, Error> { "launch-existing" }
        _ = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task1)

        // When: Another bundle tries to create launch
        var task2Created = false
        let task2 = Task<String, Error> {
            task2Created = true
            return "launch-should-not-be-used"
        }

        let launchID = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task2)

        // Then: Should return existing ID without executing new task
        XCTAssertEqual(launchID, "launch-existing", "Should return existing launch ID")
        // Note: task2Created might be true if task started before actor check, but result won't be used
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
        _ = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task)

        // When: Get launch ID
        let launchID = await LaunchManager.shared.getLaunchID()

        // Then: Should return launch ID
        XCTAssertEqual(launchID, "launch-789", "Should return created launch ID")
    }

    func testGetOrAwaitLaunchID_RetryAfterFailure() async throws {
        // Given: First task fails
        let task1 = Task<String, Error> {
            throw NSError(domain: "TestError", code: 1, userInfo: [NSLocalizedDescriptionKey: "Network error"])
        }

        do {
            _ = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task1)
            XCTFail("Should throw error")
        } catch {
            // Expected failure
        }

        // When: Second task succeeds
        let task2 = Task<String, Error> { "launch-retry-success" }
        let launchID = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task2)

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
        await LaunchManager.shared.incrementBundleCount()
        let task = Task<String, Error> { "launch-reset" }
        _ = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task)
        await LaunchManager.shared.updateStatus(.failed)
        await LaunchManager.shared.markFinalized()

        // When: Reset
        await LaunchManager.shared.reset()

        // Then: All state should be cleared
        let count = await LaunchManager.shared.getActiveBundleCount()
        let launchID = await LaunchManager.shared.getLaunchID()
        let status = await LaunchManager.shared.getAggregatedStatus()
        let isFinalized = await LaunchManager.shared.isLaunchFinalized()

        XCTAssertEqual(count, 0, "Count should be reset to 0")
        XCTAssertNil(launchID, "Launch ID should be nil")
        XCTAssertEqual(status, .passed, "Status should be reset to passed")
        XCTAssertFalse(isFinalized, "Finalized flag should be reset")
    }

    // MARK: - Integration Tests

    func testFullLaunchLifecycle() async throws {
        // Given: 3 test bundles

        // When: Bundles start
        await LaunchManager.shared.incrementBundleCount()
        await LaunchManager.shared.incrementBundleCount()
        await LaunchManager.shared.incrementBundleCount()

        // Create launch (first bundle wins)
        let task = Task<String, Error> { "launch-lifecycle" }
        let launchID = try await LaunchManager.shared.getOrAwaitLaunchID(launchTask: task)
        XCTAssertEqual(launchID, "launch-lifecycle")

        // Update statuses from tests
        await LaunchManager.shared.updateStatus(.passed)
        await LaunchManager.shared.updateStatus(.failed)
        await LaunchManager.shared.updateStatus(.passed)

        // Bundles finish (2, 3, 1 order - simulating parallel execution)
        var shouldFinalize = await LaunchManager.shared.decrementBundleCount()
        XCTAssertFalse(shouldFinalize, "Bundle 1 finish: should not finalize")

        shouldFinalize = await LaunchManager.shared.decrementBundleCount()
        XCTAssertFalse(shouldFinalize, "Bundle 2 finish: should not finalize")

        shouldFinalize = await LaunchManager.shared.decrementBundleCount()
        XCTAssertTrue(shouldFinalize, "Bundle 3 finish: should finalize")

        // Check final state
        let finalStatus = await LaunchManager.shared.getAggregatedStatus()
        XCTAssertEqual(finalStatus, .failed, "Should aggregate to failed")

        // Mark finalized
        await LaunchManager.shared.markFinalized()
        let isFinalized = await LaunchManager.shared.isLaunchFinalized()
        XCTAssertTrue(isFinalized)
    }
}
