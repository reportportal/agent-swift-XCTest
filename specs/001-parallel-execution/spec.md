# Feature Specification: Parallel Test Execution Support

**Feature Branch**: `001-parallel-execution`  
**Created**: 2025-10-16  
**Status**: Draft  
**Input**: User description: "We now have to support Parallel execution for tests on this framework. please analyse all code to understand current limitations. Currently due to specifics of starting implementation it's not possible to run tests in parallel."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Concurrent Test Suite Execution (Priority: P1)

As a developer running XCTest suites, I want to execute multiple test suites in parallel so that my CI/CD pipeline completes faster (reducing 4.5-6 hour runs to 1-2 hours).

**Why this priority**: Core feature requirement. Current sequential execution causes significant time bottlenecks in CI/CD pipelines. Parallel execution can reduce total execution time by 2-4x depending on CI capabilities.

**Independent Test**: Can be fully tested by configuring Xcode test plan with parallel execution enabled, running 3+ test suites concurrently, and verifying all tests report correctly to ReportPortal with proper hierarchy and no data corruption.

**Acceptance Scenarios**:

1. **Given** 3 test suites configured for parallel execution, **When** tests run concurrently, **Then** each test's results appear correctly in ReportPortal under the same launch with proper suite/test hierarchy
2. **Given** parallel tests running, **When** one test fails, **Then** the failure is reported correctly without affecting other concurrent tests' reporting
3. **Given** parallel execution enabled, **When** tests complete, **Then** launch finalization happens only after ALL test bundles finish (respecting IsFinalTestBundle flag)

---

### User Story 2 - Individual Test Case Concurrency (Priority: P2)

As a developer with independent test cases, I want individual test methods within a suite to run in parallel so that suite execution time is further optimized.

**Why this priority**: Secondary optimization after suite-level parallelism works. Provides additional performance gains for suites with many independent test cases.

**Independent Test**: Configure a single test suite with 10+ independent test cases to run in parallel, verify all cases report correctly with proper parent suite association.

**Acceptance Scenarios**:

1. **Given** test suite with 10 independent test cases running in parallel, **When** execution completes, **Then** all 10 test cases appear under correct suite in ReportPortal
2. **Given** concurrent test cases, **When** multiple cases log attachments simultaneously, **Then** each attachment is associated with correct test case

---

### User Story 3 - Performance Improvement (Priority: P1)

As a CI/CD engineer, I want test execution time reduced from 6 hours to 1-2 hours so that developer feedback cycles are faster and CI resources are used efficiently.

**Why this priority**: Primary business value. Current 6-hour runs are unsustainable and directly impact developer productivity.

**Independent Test**: Measure baseline sequential execution time, enable parallel execution, measure new execution time. Success = 50-75% reduction in total time.

**Acceptance Scenarios**:

1. **Given** baseline 6-hour sequential test run, **When** parallel execution is enabled on CI with 4 parallel workers, **Then** total execution time is reduced to 1.5-2 hours
2. **Given** parallel execution enabled, **When** ReportPortal server is slow/errors, **Then** tests continue without blocking each other (non-blocking async operations)

---

### Edge Cases

- **Slow/Failed ReportPortal API**: When ReportPortal API is slow or returns errors during parallel execution, individual test reporting failures must be logged to console but not block other tests. Each test operation handles its own errors independently.
- **Concurrent Launch Status Updates**: Race conditions when multiple tests finish simultaneously are prevented by Actor isolation in LaunchManager. Status aggregation uses atomic operations within the actor.
- **Out-of-Order Bundle Completion**: Reference counting handles non-final bundles completing after final bundle. LaunchManager maintains active bundle count; finalization triggers only when count reaches zero.
- **Launch Finalization with IsFinalTestBundle**: The IsFinalTestBundle flag is respected but not solely relied upon. Each bundle increments reference count on start and decrements on finish. Launch finalizes when count reaches zero, ensuring all bundles have completed.
- **Test Name Collisions**: Parallel tests with identical identifiers are disambiguated using XCTest's internal test identifier which includes bundle + suite + case hierarchy. OperationTracker uses full qualified identifiers as keys.
- **Catastrophic Bundle Failure**: If a bundle crashes before decrementing reference count, a timeout mechanism (configurable, default 30 minutes) forces finalization to prevent hung launches. Edge case already addressed in reference counting strategy.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST support concurrent execution of multiple test suites without data corruption or race conditions
- **FR-002**: System MUST maintain proper test hierarchy (Launch → Suite → Test Case) in ReportPortal even when tests run in parallel
- **FR-003**: System MUST isolate state per test operation (each test gets independent context - IDs, status, metadata)
- **FR-004**: System MUST use non-blocking async operations for all ReportPortal API calls (remove DispatchSemaphore blocking)
- **FR-005**: System MUST aggregate launch status correctly from multiple concurrent test operations using Actor-isolated state
- **FR-006**: System MUST handle launch finalization using reference counting: each bundle increments counter on start, decrements on finish; finalization triggers when counter reaches zero
- **FR-007**: System MUST support both suite-level and test-case-level parallelism
- **FR-008**: System MUST maintain backward compatibility with sequential execution (parallel execution is opt-in)
- **FR-009**: System MUST provide thread-safe operations for all shared resources using Swift Actor isolation (LaunchManager, OperationTracker as Actors)
- **FR-010**: System MUST handle concurrent attachment uploads without mixing data between tests
- **FR-011**: System MUST use Actor model for shared mutable state to prevent race conditions at compile time

### Key Entities *(include if feature involves data)*

- **TestOperation**: Represents a single test execution context with isolated state (test ID, suite ID, status, metadata, correlation ID for logging). Lifecycle matches XCTest test case execution. Implemented as struct (value type, no shared state).
- **SuiteOperation**: Represents a test suite execution context managing hierarchy (root suite ID, test suite ID, child tests, correlation ID). Handles parent-child relationships. Implemented as struct (value type).
- **LaunchManager**: Shared actor managing launch-level state (launch ID, aggregated status, finalization flag, active bundle reference count). Thread-safe operations enforced by Actor isolation. Singleton pattern with actor semantics. Implements reference counting for finalization coordination.
- **OperationTracker**: Actor-based registry tracking active test/suite operations. Maps XCTest identifiers to operation objects with thread-safe access.
- **Logger**: Structured logging utility supporting correlation IDs, timestamps, and thread context. Logs operation lifecycle events (start, finish, errors) for debugging parallel execution.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Test execution time reduces from 6 hours to 1.5-2 hours with 4 parallel workers (60-75% reduction)
- **SC-002**: Zero data corruption or race conditions observed in 100 parallel test runs with up to 10 concurrent operations
- **SC-003**: All parallel test results appear correctly in ReportPortal with proper hierarchy (100% accuracy)
- **SC-004**: Backward compatibility maintained - existing sequential test configurations continue working without changes
- **SC-005**: API call blocking time reduced to zero - no DispatchSemaphore waits blocking test execution threads

## Non-Functional Requirements

### Performance

- **NFR-001**: ReportPortal API operations must be fully asynchronous and non-blocking using async/await
- **NFR-002**: No artificial waits or semaphore blocks (current 10-second blocking waits must be eliminated)
- **NFR-003**: System must support up to 10 concurrent test operations without degradation (based on typical CI environments with 4 parallel workers)
- **NFR-004**: Memory usage must not exceed 2x baseline when running with 10 concurrent operations

### Observability

- **NFR-012**: All test operation lifecycle events (start, finish, errors) MUST be logged with structured format
- **NFR-013**: Each test operation MUST have unique correlation ID propagated through all related log entries
- **NFR-014**: Logs MUST include timestamps, thread context, operation type, and ReportPortal IDs for traceability
- **NFR-015**: Error logs MUST include full context (test name, correlation ID, API endpoint, error details) for debugging

### Reliability

- **NFR-005**: Network failures or ReportPortal API errors must not crash test execution or corrupt other tests' data
- **NFR-006**: Race condition detection via thread sanitizer must pass with zero warnings
- **NFR-007**: Launch finalization must be atomic and execute exactly once even with concurrent bundle completions

### Maintainability

- **NFR-008**: Refactored code must maintain current architecture patterns (EndPoints, Entities, Utilities structure)
- **NFR-009**: Breaking changes to public APIs should be avoided; if necessary, must be documented in migration guide with MAJOR version bump (4.0.0)
- **NFR-010**: Use Swift Concurrency primitives (async/await, Task, Actor) following Swift 5.5+ best practices
- **NFR-011**: Minimum deployment target: iOS 13+, macOS 10.15+ (required for Swift Concurrency runtime)

## Current Architecture Limitations

### Critical Blockers

1. **Shared State in ReportingService**: Instance variables overwritten by concurrent tests
   - `private var launchID: String?`
   - `private var rootSuiteID: String?`
   - `private var testSuiteID: String?`
   - `private var testID = ""`
   - `private var testSuiteStatus = TestStatus.passed`
   - `private var launchStatus = TestStatus.passed`

2. **Blocking Synchronous Operations**: DispatchSemaphore blocks threads (up to 10 seconds per operation)
   - Causes priority inversion warnings
   - Main XCTest thread waits on background reporting queue
   - Stacks up delays when ReportPortal is slow

3. **Single Service Instance**: One ReportingService handles all tests
   - Race conditions when multiple tests call same methods
   - No isolation between concurrent test executions
   - Status updates overwrite each other

### iOS-Specific Constraints

- **Test Plan Name Access**: Unlike Android, iOS requires environment variables for test plan metadata
  - XCTest doesn't expose test plan info via runtime APIs
  - Build-time configuration must pass through environment variables
  - Already supported via `TEST_PLAN_NAME` env var (working correctly)

## Technical Constraints

- **Minimum Swift Version**: Swift 5.5+ (required for async/await and structured concurrency)
- **Swift Concurrency**: Use async/await, Task-based concurrency, and potentially Actor model for thread-safe state
- **Target Platforms**: iOS 13+, macOS 10.15+ (minimum for Swift Concurrency runtime support)
- **XCTest Observation**: Must maintain XCTestObservation protocol compliance
- **ReportPortal API**: v1 (existing endpoints support concurrent requests)
- **Backward Compatibility**: Must support both CocoaPods and SPM distribution
- **Package.swift**: Update swift-tools-version from 5.1 to 5.5

## Out of Scope

- Changes to ReportPortal server API or behavior
- Modifications to XCTest framework or Xcode test runner
- Performance optimizations unrelated to parallel execution
- New ReportPortal features beyond parallel test support

## Clarifications

### Session 2025-10-16

- Q: Should we require Swift 5.5+ for async/await or maintain Swift 5.1 compatibility with completion handlers? → A: Swift 5.5+ with async/await and Task-based concurrency
- Q: For managing concurrent test operations, what thread-safe state management strategy should be used? → A: Actor model for shared state (LaunchManager as Actor, thread-safe by design)
- Q: What strategy should be used for launch finalization coordination when test bundles finish out of order? → A: Reference counting with atomic finalization (each bundle increments on start, decrements on finish; finalize at zero)
- Q: What logging strategy should be used for debugging parallel execution issues? → A: Structured logging with correlation IDs per test operation (trace test lifecycle across threads)
- Q: What is the maximum expected number of concurrent tests in real-world CI environments? → A: 10 concurrent operations maximum

## Open Questions / Needs Clarification

- Should we support dynamic parallelism configuration or require test plan/Xcode configuration? - Yes
- What is the acceptable memory overhead for parallel execution? (current baseline: 2x at 10 concurrent operations)
