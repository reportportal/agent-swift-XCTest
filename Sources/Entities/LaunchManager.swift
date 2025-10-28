//
//  LaunchManager.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation

/// Thread-safe launch-level state management with reference counting.
/// Manages launch lifecycle across multiple concurrent test bundles.
actor LaunchManager {
    /// Shared singleton instance
    static let shared = LaunchManager()

    /// Private initializer ensures singleton pattern
    private init() {}

    // MARK: - Private State

    /// ReportPortal launch ID (shared across all bundles)
    private var launchID: String?

    /// Shared Task for launch creation (allows multiple bundles to await same operation)
    private var launchCreationTask: Task<String, Error>?

    /// Number of active test bundles (for reference counting)
    private var activeBundleCount: Int = 0

    /// Overall launch status (worst of all tests)
    private var aggregatedStatus: TestStatus = .passed

    /// Whether launch has been finalized
    private var isFinalized: Bool = false

    /// Launch start timestamp
    private var launchStartTime: Date?

    // MARK: - Bundle Lifecycle

    /// Increment active bundle counter when test bundle starts
    func incrementBundleCount() {
        activeBundleCount += 1
    }

    /// Decrement active bundle counter when test bundle finishes
    /// - Returns: `true` if count reached zero (should finalize launch), `false` otherwise
    func decrementBundleCount() -> Bool {
        activeBundleCount -= 1
        return activeBundleCount == 0
    }

    /// Get current active bundle count (for diagnostics)
    /// - Returns: Current value of activeBundleCount
    func getActiveBundleCount() -> Int {
        return activeBundleCount
    }

    // MARK: - Launch Management

    /// Get or await launch ID
    /// Multiple bundles calling this will await the same launch creation
    /// - Parameter launchTask: Task that creates the launch (passed from caller)
    /// - Returns: Launch ID (either existing or from task)
    func getOrAwaitLaunchID(launchTask: Task<String, Error>) async throws -> String {
        // If launch already exists, return it immediately
        if let existingID = launchID {
            // Cancel the new task since we don't need it
            launchTask.cancel()
            return existingID
        }

        // If launch creation is in progress, await the existing task
        if let existingTask = launchCreationTask {
            // Cancel the new task since we already have one
            launchTask.cancel()
            return try await existingTask.value
        }

        // Store the task so other bundles can await it
        launchCreationTask = launchTask

        // Await the result
        do {
            let id = try await launchTask.value
            self.launchID = id
            if self.launchStartTime == nil {
                self.launchStartTime = Date()
            }
            return id
        } catch {
            // Clear task on failure so another bundle can retry
            launchCreationTask = nil
            throw error
        }
    }

    /// Retrieve current launch ID (non-blocking check)
    /// - Returns: Launch ID if set, `nil` if launch not yet started
    func getLaunchID() -> String? {
        return launchID
    }

    // MARK: - Status Aggregation

    /// Update aggregated launch status (worst status wins)
    /// - Parameter newStatus: Status from completed test
    /// Status priority: .failed > .skipped > .passed
    func updateStatus(_ newStatus: TestStatus) {
        // Convert status to severity for comparison
        let currentSeverity = statusSeverity(aggregatedStatus)
        let newSeverity = statusSeverity(newStatus)

        if newSeverity > currentSeverity {
            aggregatedStatus = newStatus
        }
    }

    /// Get current aggregated launch status
    /// - Returns: Worst status seen across all completed tests
    func getAggregatedStatus() -> TestStatus {
        return aggregatedStatus
    }

    // MARK: - Finalization

    /// Mark launch as finalized (prevent duplicate finalization)
    func markFinalized() {
        isFinalized = true
    }

    /// Check if launch has been finalized
    /// - Returns: `true` if finalized, `false` otherwise
    func isLaunchFinalized() -> Bool {
        return isFinalized
    }

    /// Reset state for next launch (if agent is reused)
    func reset() {
        launchID = nil
        launchCreationTask = nil
        activeBundleCount = 0
        aggregatedStatus = .passed
        isFinalized = false
        launchStartTime = nil
    }

    // MARK: - Private Helpers

    /// Convert status to severity level for comparison
    /// - Parameter status: Test status
    /// - Returns: Severity level (higher = worse)
    private func statusSeverity(_ status: TestStatus) -> Int {
        switch status {
        case .failed:
            return 3
        case .stopped, .cancelled:
            return 2
        case .skipped:
            return 1
        case .passed, .reseted:
            return 0
        }
    }
}
