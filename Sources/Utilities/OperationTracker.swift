//
//  OperationTracker.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation

/// Thread-safe registry for active test and suite operations.
/// Manages operation lifecycle and provides diagnostics for parallel execution.
actor OperationTracker {
    /// Shared singleton instance
    static let shared = OperationTracker()

    /// Private initializer ensures singleton pattern
    private init() {}

    // MARK: - Configuration

    /// Maximum recommended concurrent operations (tests + suites)
    /// Exceeding this limit may cause memory pressure and performance degradation
    private let maxRecommendedOperations: Int = 10

    // MARK: - Private State

    /// Active test operations (key: XCTest identifier)
    private var testOperations: [String: TestOperation] = [:]

    /// Active suite operations (key: suite identifier)
    private var suiteOperations: [String: SuiteOperation] = [:]

    /// Peak concurrent operation count (for diagnostics)
    private var peakOperationCount: Int = 0

    // MARK: - Test Operation Management

    /// Register a test operation at test start
    /// - Parameters:
    ///   - operation: TestOperation struct with correlation ID, test ID, metadata
    ///   - identifier: Unique XCTest identifier (format: "Bundle.Class.testMethod")
    func registerTest(_ operation: TestOperation, identifier: String) {
        testOperations[identifier] = operation

        // T024: Check concurrency limit and log warning
        checkConcurrencyLimit()
    }

    /// Retrieve test operation for given identifier
    /// - Parameter identifier: XCTest identifier
    /// - Returns: TestOperation if found, `nil` if not registered
    func getTest(identifier: String) -> TestOperation? {
        return testOperations[identifier]
    }

    /// Update existing test operation (e.g., status change, add attachment)
    /// - Parameters:
    ///   - operation: Updated TestOperation struct
    ///   - identifier: XCTest identifier
    func updateTest(_ operation: TestOperation, identifier: String) {
        testOperations[identifier] = operation
    }

    /// Remove test operation after reporting complete
    /// - Parameter identifier: XCTest identifier
    func unregisterTest(identifier: String) {
        testOperations.removeValue(forKey: identifier)
    }

    // MARK: - Suite Operation Management

    /// Register a suite operation at suite start
    /// - Parameters:
    ///   - operation: SuiteOperation struct with correlation ID, suite ID, metadata
    ///   - identifier: Unique XCTest suite identifier (format: "Bundle.Class")
    func registerSuite(_ operation: SuiteOperation, identifier: String) {
        suiteOperations[identifier] = operation

        // T024: Check concurrency limit and log warning
        checkConcurrencyLimit()
    }

    /// Retrieve suite operation for given identifier
    /// - Parameter identifier: XCTest suite identifier
    /// - Returns: SuiteOperation if found, `nil` if not registered
    func getSuite(identifier: String) -> SuiteOperation? {
        return suiteOperations[identifier]
    }

    /// Update existing suite operation (e.g., add child test, update status)
    /// - Parameters:
    ///   - operation: Updated SuiteOperation struct
    ///   - identifier: XCTest suite identifier
    func updateSuite(_ operation: SuiteOperation, identifier: String) {
        suiteOperations[identifier] = operation
    }

    /// Remove suite operation after reporting complete
    /// - Parameter identifier: XCTest suite identifier
    func unregisterSuite(identifier: String) {
        suiteOperations.removeValue(forKey: identifier)
    }

    // MARK: - Diagnostics

    /// Get count of currently active (registered) test operations
    /// - Returns: Number of entries in testOperations dictionary
    func getActiveTestCount() -> Int {
        return testOperations.count
    }

    /// Get count of currently active (registered) suite operations
    /// - Returns: Number of entries in suiteOperations dictionary
    func getActiveSuiteCount() -> Int {
        return suiteOperations.count
    }

    /// Get all active test identifiers (for debugging)
    /// - Returns: Array of test identifier strings
    func getAllTestIdentifiers() -> [String] {
        return Array(testOperations.keys)
    }

    /// Get all active suite identifiers (for debugging)
    /// - Returns: Array of suite identifier strings
    func getAllSuiteIdentifiers() -> [String] {
        return Array(suiteOperations.keys)
    }

    /// Clear all operations (for testing or launch cleanup)
    func reset() {
        testOperations.removeAll()
        suiteOperations.removeAll()
        peakOperationCount = 0
    }

    /// Get peak concurrent operation count since tracker initialization
    /// - Returns: Maximum number of operations active at any point
    func getPeakOperationCount() -> Int {
        return peakOperationCount
    }

    // MARK: - Private Helper Methods

    /// Check if current operation count exceeds recommended limit and log warning
    /// Called after registerTest() and registerSuite()
    private func checkConcurrencyLimit() {
        let totalOperations = testOperations.count + suiteOperations.count

        // Update peak count
        if totalOperations > peakOperationCount {
            peakOperationCount = totalOperations
        }

        // Log warning if approaching or exceeding limit
        if totalOperations >= maxRecommendedOperations {
            Logger.shared.warning(
                """
                Concurrency limit reached: \(totalOperations) active operations (recommended max: \(maxRecommendedOperations))
                - Active tests: \(testOperations.count)
                - Active suites: \(suiteOperations.count)
                - Peak operations: \(peakOperationCount)
                Consider reducing maximumParallelTestExecutionWorkers in .xctestplan to improve stability.
                """
            )
        } else if totalOperations >= Int(Double(maxRecommendedOperations) * 0.8) {
            // Log info when reaching 80% of limit
            Logger.shared.info(
                "High concurrency: \(totalOperations)/\(maxRecommendedOperations) active operations (tests: \(testOperations.count), suites: \(suiteOperations.count))"
            )
        }
    }
}
