//
//  OperationTrackerTests.swift
//  ExampleUnitTests
//
//  Created for ReportPortal Agent v4.0
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest
@testable import ReportPortalAgent

/// Unit tests for OperationTracker actor
/// Tests thread-safe operation registry for concurrent test/suite operations
final class OperationTrackerTests: XCTestCase {

    // MARK: - Test Lifecycle

    override func setUp() async throws {
        // Reset OperationTracker state before each test
        await OperationTracker.shared.reset()
    }

    // MARK: - Test Operation Management

    func testRegisterTest() async {
        // Given: Test operation
        let operation = TestOperation(
            correlationID: UUID(),
            testID: "test-001",
            suiteID: "suite-001",
            testName: "testExample",
            className: "MyTestClass"
        )

        // When: Register test
        await OperationTracker.shared.registerTest(operation, identifier: "MyTestClass.testExample")

        // Then: Test should be retrievable
        let retrieved = await OperationTracker.shared.getTest(identifier: "MyTestClass.testExample")
        XCTAssertNotNil(retrieved, "Test should be registered")
        XCTAssertEqual(retrieved?.testID, "test-001", "Test ID should match")
        XCTAssertEqual(retrieved?.testName, "testExample", "Test name should match")
    }

    func testGetTest_ReturnsNilForUnregistered() async {
        // Given: No test registered

        // When: Get non-existent test
        let retrieved = await OperationTracker.shared.getTest(identifier: "NonExistent.test")

        // Then: Should return nil
        XCTAssertNil(retrieved, "Should return nil for unregistered test")
    }

    func testUpdateTest() async {
        // Given: Registered test
        var operation = TestOperation(
            correlationID: UUID(),
            testID: "test-002",
            suiteID: "suite-001",
            testName: "testUpdate",
            className: "UpdateTestClass",
            status: .passed
        )
        await OperationTracker.shared.registerTest(operation, identifier: "UpdateTestClass.testUpdate")

        // When: Update test status
        operation.status = .failed
        await OperationTracker.shared.updateTest(operation, identifier: "UpdateTestClass.testUpdate")

        // Then: Updated test should be retrievable
        let retrieved = await OperationTracker.shared.getTest(identifier: "UpdateTestClass.testUpdate")
        XCTAssertEqual(retrieved?.status, .failed, "Status should be updated to failed")
    }

    func testUnregisterTest() async {
        // Given: Registered test
        let operation = TestOperation(
            correlationID: UUID(),
            testID: "test-003",
            suiteID: "suite-001",
            testName: "testUnregister",
            className: "UnregisterTestClass"
        )
        await OperationTracker.shared.registerTest(operation, identifier: "UnregisterTestClass.testUnregister")

        // When: Unregister test
        await OperationTracker.shared.unregisterTest(identifier: "UnregisterTestClass.testUnregister")

        // Then: Test should no longer be retrievable
        let retrieved = await OperationTracker.shared.getTest(identifier: "UnregisterTestClass.testUnregister")
        XCTAssertNil(retrieved, "Test should be unregistered")
    }

    func testGetActiveTestCount() async {
        // Given: Multiple tests registered
        for i in 1...5 {
            let operation = TestOperation(
                correlationID: UUID(),
                testID: "test-\(i)",
                suiteID: "suite-001",
                testName: "test\(i)",
                className: "TestClass"
            )
            await OperationTracker.shared.registerTest(operation, identifier: "TestClass.test\(i)")
        }

        // When: Get active test count
        let count = await OperationTracker.shared.getActiveTestCount()

        // Then: Should match registered count
        XCTAssertEqual(count, 5, "Should have 5 active tests")
    }

    func testGetAllTestIdentifiers() async {
        // Given: Multiple tests registered
        let identifiers = ["TestClass.test1", "TestClass.test2", "TestClass.test3"]
        for (index, identifier) in identifiers.enumerated() {
            let operation = TestOperation(
                correlationID: UUID(),
                testID: "test-\(index + 1)",
                suiteID: "suite-001",
                testName: "test\(index + 1)",
                className: "TestClass"
            )
            await OperationTracker.shared.registerTest(operation, identifier: identifier)
        }

        // When: Get all identifiers
        let allIdentifiers = await OperationTracker.shared.getAllTestIdentifiers()

        // Then: Should contain all registered identifiers
        XCTAssertEqual(Set(allIdentifiers), Set(identifiers), "Should return all registered identifiers")
    }

    // MARK: - Suite Operation Management

    func testRegisterSuite() async {
        // Given: Suite operation
        let operation = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-001",
            rootSuiteID: nil,
            suiteName: "MySuiteClass",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )

        // When: Register suite
        await OperationTracker.shared.registerSuite(operation, identifier: "MySuiteClass")

        // Then: Suite should be retrievable
        let retrieved = await OperationTracker.shared.getSuite(identifier: "MySuiteClass")
        XCTAssertNotNil(retrieved, "Suite should be registered")
        XCTAssertEqual(retrieved?.suiteID, "suite-001", "Suite ID should match")
        XCTAssertEqual(retrieved?.suiteName, "MySuiteClass", "Suite name should match")
    }

    func testGetSuite_ReturnsNilForUnregistered() async {
        // Given: No suite registered

        // When: Get non-existent suite
        let retrieved = await OperationTracker.shared.getSuite(identifier: "NonExistentSuite")

        // Then: Should return nil
        XCTAssertNil(retrieved, "Should return nil for unregistered suite")
    }

    func testUpdateSuite() async {
        // Given: Registered suite
        var operation = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-002",
            rootSuiteID: nil,
            suiteName: "UpdateSuite",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )
        await OperationTracker.shared.registerSuite(operation, identifier: "UpdateSuite")

        // When: Update suite with child tests
        operation.childTestIDs.append("test-001")
        operation.childTestIDs.append("test-002")
        await OperationTracker.shared.updateSuite(operation, identifier: "UpdateSuite")

        // Then: Updated suite should be retrievable
        let retrieved = await OperationTracker.shared.getSuite(identifier: "UpdateSuite")
        XCTAssertEqual(retrieved?.childTestIDs.count, 2, "Should have 2 child tests")
    }

    func testUnregisterSuite() async {
        // Given: Registered suite
        let operation = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-003",
            rootSuiteID: nil,
            suiteName: "UnregisterSuite",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )
        await OperationTracker.shared.registerSuite(operation, identifier: "UnregisterSuite")

        // When: Unregister suite
        await OperationTracker.shared.unregisterSuite(identifier: "UnregisterSuite")

        // Then: Suite should no longer be retrievable
        let retrieved = await OperationTracker.shared.getSuite(identifier: "UnregisterSuite")
        XCTAssertNil(retrieved, "Suite should be unregistered")
    }

    func testGetActiveSuiteCount() async {
        // Given: Multiple suites registered
        for i in 1...3 {
            let operation = SuiteOperation(
                correlationID: UUID(),
                suiteID: "suite-\(i)",
                rootSuiteID: nil,
                suiteName: "Suite\(i)",
                status: .passed,
                startTime: Date(),
                childTestIDs: [],
                metadata: [:]
            )
            await OperationTracker.shared.registerSuite(operation, identifier: "Suite\(i)")
        }

        // When: Get active suite count
        let count = await OperationTracker.shared.getActiveSuiteCount()

        // Then: Should match registered count
        XCTAssertEqual(count, 3, "Should have 3 active suites")
    }

    func testGetAllSuiteIdentifiers() async {
        // Given: Multiple suites registered
        let identifiers = ["Suite1", "Suite2", "Suite3"]
        for (index, identifier) in identifiers.enumerated() {
            let operation = SuiteOperation(
                correlationID: UUID(),
                suiteID: "suite-\(index + 1)",
                rootSuiteID: nil,
                suiteName: identifier,
                status: .passed,
                startTime: Date(),
                childTestIDs: [],
                metadata: [:]
            )
            await OperationTracker.shared.registerSuite(operation, identifier: identifier)
        }

        // When: Get all identifiers
        let allIdentifiers = await OperationTracker.shared.getAllSuiteIdentifiers()

        // Then: Should contain all registered identifiers
        XCTAssertEqual(Set(allIdentifiers), Set(identifiers), "Should return all registered suite identifiers")
    }

    // MARK: - Concurrency Tests

    func testConcurrentTestRegistration() async {
        // Given: Multiple concurrent test registrations
        let testCount = 20

        // When: Register tests concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<testCount {
                group.addTask {
                    let operation = TestOperation(
                        correlationID: UUID(),
                        testID: "test-\(i)",
                        suiteID: "suite-001",
                        testName: "test\(i)",
                        className: "ConcurrentTestClass"
                    )
                    await OperationTracker.shared.registerTest(operation, identifier: "ConcurrentTestClass.test\(i)")
                }
            }
        }

        // Then: All tests should be registered (no race conditions)
        let count = await OperationTracker.shared.getActiveTestCount()
        XCTAssertEqual(count, testCount, "All concurrent registrations should succeed")
    }

    func testConcurrentSuiteRegistration() async {
        // Given: Multiple concurrent suite registrations
        let suiteCount = 10

        // When: Register suites concurrently
        await withTaskGroup(of: Void.self) { group in
            for i in 0..<suiteCount {
                group.addTask {
                    let operation = SuiteOperation(
                        correlationID: UUID(),
                        suiteID: "suite-\(i)",
                        rootSuiteID: nil,
                        suiteName: "ConcurrentSuite\(i)",
                        status: .passed,
                        startTime: Date(),
                        childTestIDs: [],
                        metadata: [:]
                    )
                    await OperationTracker.shared.registerSuite(operation, identifier: "ConcurrentSuite\(i)")
                }
            }
        }

        // Then: All suites should be registered (no race conditions)
        let count = await OperationTracker.shared.getActiveSuiteCount()
        XCTAssertEqual(count, suiteCount, "All concurrent registrations should succeed")
    }

    func testConcurrentReadWrite() async {
        // Given: Test registered
        let operation = TestOperation(
            correlationID: UUID(),
            testID: "test-rw",
            suiteID: "suite-001",
            testName: "testReadWrite",
            className: "ReadWriteClass",
            status: .passed
        )
        await OperationTracker.shared.registerTest(operation, identifier: "ReadWriteClass.testReadWrite")

        // When: Concurrent reads and writes
        await withTaskGroup(of: Void.self) { group in
            // 10 readers
            for _ in 0..<10 {
                group.addTask {
                    _ = await OperationTracker.shared.getTest(identifier: "ReadWriteClass.testReadWrite")
                }
            }

            // 5 writers
            for i in 0..<5 {
                group.addTask {
                    var op = operation
                    op.status = i % 2 == 0 ? .passed : .failed
                    await OperationTracker.shared.updateTest(op, identifier: "ReadWriteClass.testReadWrite")
                }
            }
        }

        // Then: Should complete without crashes (actor serializes access)
        let retrieved = await OperationTracker.shared.getTest(identifier: "ReadWriteClass.testReadWrite")
        XCTAssertNotNil(retrieved, "Test should still be accessible after concurrent access")
    }

    // MARK: - Peak Operation Count Tests

    func testPeakOperationCount() async {
        // Given: Register and unregister operations

        // Register 5 tests
        for i in 1...5 {
            let operation = TestOperation(
                correlationID: UUID(),
                testID: "test-\(i)",
                suiteID: "suite-001",
                testName: "test\(i)",
                className: "PeakTestClass"
            )
            await OperationTracker.shared.registerTest(operation, identifier: "PeakTestClass.test\(i)")
        }

        // Register 3 suites
        for i in 1...3 {
            let operation = SuiteOperation(
                correlationID: UUID(),
                suiteID: "suite-\(i)",
                rootSuiteID: nil,
                suiteName: "PeakSuite\(i)",
                status: .passed,
                startTime: Date(),
                childTestIDs: [],
                metadata: [:]
            )
            await OperationTracker.shared.registerSuite(operation, identifier: "PeakSuite\(i)")
        }

        // Peak should be 8 (5 tests + 3 suites)
        var peak = await OperationTracker.shared.getPeakOperationCount()
        XCTAssertEqual(peak, 8, "Peak should be 8 operations")

        // Unregister 3 tests
        await OperationTracker.shared.unregisterTest(identifier: "PeakTestClass.test1")
        await OperationTracker.shared.unregisterTest(identifier: "PeakTestClass.test2")
        await OperationTracker.shared.unregisterTest(identifier: "PeakTestClass.test3")

        // Peak should still be 8 (doesn't decrease)
        peak = await OperationTracker.shared.getPeakOperationCount()
        XCTAssertEqual(peak, 8, "Peak should remain at 8 even after unregistering")
    }

    // MARK: - Reset Tests

    func testReset_ClearsAllState() async {
        // Given: Operations registered
        let testOp = TestOperation(
            correlationID: UUID(),
            testID: "test-reset",
            suiteID: "suite-001",
            testName: "testReset",
            className: "ResetClass"
        )
        await OperationTracker.shared.registerTest(testOp, identifier: "ResetClass.testReset")

        let suiteOp = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-reset",
            rootSuiteID: nil,
            suiteName: "ResetSuite",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )
        await OperationTracker.shared.registerSuite(suiteOp, identifier: "ResetSuite")

        // When: Reset
        await OperationTracker.shared.reset()

        // Then: All state should be cleared
        let testCount = await OperationTracker.shared.getActiveTestCount()
        let suiteCount = await OperationTracker.shared.getActiveSuiteCount()
        let peak = await OperationTracker.shared.getPeakOperationCount()

        XCTAssertEqual(testCount, 0, "Test count should be 0 after reset")
        XCTAssertEqual(suiteCount, 0, "Suite count should be 0 after reset")
        XCTAssertEqual(peak, 0, "Peak count should be 0 after reset")
    }

    // MARK: - Integration Tests

    func testFullOperationLifecycle() async {
        // Given: Complete test hierarchy

        // Register root suite
        let rootSuite = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-root",
            rootSuiteID: nil,
            suiteName: "RootSuite.xctest",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )
        await OperationTracker.shared.registerSuite(rootSuite, identifier: "RootSuite.xctest")

        // Register test class suite
        let testClassSuite = SuiteOperation(
            correlationID: UUID(),
            suiteID: "suite-testclass",
            rootSuiteID: "suite-root",
            suiteName: "MyTestClass",
            status: .passed,
            startTime: Date(),
            childTestIDs: [],
            metadata: [:]
        )
        await OperationTracker.shared.registerSuite(testClassSuite, identifier: "MyTestClass")

        // Register tests
        for i in 1...3 {
            let test = TestOperation(
                correlationID: UUID(),
                testID: "test-\(i)",
                suiteID: "suite-testclass",
                testName: "test\(i)",
                className: "MyTestClass"
            )
            await OperationTracker.shared.registerTest(test, identifier: "MyTestClass.test\(i)")
        }

        // Verify hierarchy
        let tests = await OperationTracker.shared.getActiveTestCount()
        let suites = await OperationTracker.shared.getActiveSuiteCount()
        XCTAssertEqual(tests, 3, "Should have 3 tests")
        XCTAssertEqual(suites, 2, "Should have 2 suites")

        // Cleanup tests
        for i in 1...3 {
            await OperationTracker.shared.unregisterTest(identifier: "MyTestClass.test\(i)")
        }

        // Cleanup suites
        await OperationTracker.shared.unregisterSuite(identifier: "MyTestClass")
        await OperationTracker.shared.unregisterSuite(identifier: "RootSuite.xctest")

        // Verify cleanup
        let finalTests = await OperationTracker.shared.getActiveTestCount()
        let finalSuites = await OperationTracker.shared.getActiveSuiteCount()
        XCTAssertEqual(finalTests, 0, "All tests should be cleaned up")
        XCTAssertEqual(finalSuites, 0, "All suites should be cleaned up")
    }
}
