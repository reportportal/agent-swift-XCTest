# Architecture Documentation

**Version**: 4.0.0
**Last Updated**: 2025-10-27

## Table of Contents

- [Overview](#overview)
- [Architectural Principles](#architectural-principles)
- [System Architecture](#system-architecture)
- [Component Design](#component-design)
- [Concurrency Model](#concurrency-model)
- [Sequence Diagrams](#sequence-diagrams)
- [State Management](#state-management)
- [Design Rationale](#design-rationale)

---

## Overview

The ReportPortal Swift XCTest Agent v4.0 is a **parallel-execution-first** test reporting framework built on Swift Concurrency primitives. The architecture enables multiple test bundles and test cases to execute concurrently while maintaining proper test hierarchy and reporting consistency in ReportPortal.

### Key Capabilities

- **Parallel Execution**: Support for up to 10 concurrent test operations
- **Thread Safety**: Actor-based isolation for all shared mutable state
- **Non-Blocking**: Async/await throughout, zero blocking operations
- **Race-Free**: Atomic launch creation, reference-counted finalization
- **Observable**: Structured logging with correlation IDs for debugging

---

## Architectural Principles

### 1. Actor Isolation for Shared State

**Principle**: All shared mutable state is protected by Swift Actors, providing compile-time thread safety guarantees.

**Implementation**:
- `LaunchManager` (Actor) - Launch-level state coordination
- `OperationTracker` (Actor) - Active test/suite operation registry

**Rationale**: Actors eliminate data races at compile time, replacing manual locks/semaphores with language-level guarantees.

### 2. Value Semantics for Operations

**Principle**: Test and suite operations are value types (structs), ensuring no shared state between concurrent operations.

**Implementation**:
- `TestOperation` (struct) - Immutable test execution context
- `SuiteOperation` (struct) - Immutable suite execution context

**Rationale**: Value types are copied on assignment, preventing unintentional sharing across threads.

### 3. Non-Blocking Async Operations

**Principle**: No operation blocks a thread waiting for I/O or synchronization.

**Implementation**:
- All network calls use `async/await`
- Task-based coordination replaces semaphores
- Exponential backoff for polling operations

**Rationale**: Blocking operations cause priority inversion and thread pool exhaustion in parallel execution.

### 4. Reference Counting for Coordination

**Principle**: Launch finalization uses reference counting instead of "final bundle" flags.

**Implementation**:
- Each bundle increments counter on start
- Each bundle decrements counter on finish
- Finalization triggers when counter reaches zero

**Rationale**: Reference counting is order-independent, handling out-of-order bundle completion gracefully.

### 5. Structured Concurrency

**Principle**: Task ownership and cancellation are explicit, following Swift Concurrency best practices.

**Implementation**:
- Tasks created by callers, passed to actors
- Unused tasks are explicitly cancelled
- Task sharing for coordinated operations

**Rationale**: Avoids `@escaping` closures, makes concurrency boundaries explicit, enables proper cancellation.

---

## System Architecture

### High-Level Component Diagram

```mermaid
graph TB
    subgraph "XCTest Framework"
        XCTest[XCTest Runner]
    end

    subgraph "ReportPortal Agent"
        RPListener[RPListener<br/>XCTestObservation]

        subgraph "Entities (Actors)"
            LaunchMgr[LaunchManager Actor<br/>Launch Coordination]
            OpTracker[OperationTracker Actor<br/>Operation Registry]
        end

        subgraph "Services"
            ReportSvc[ReportingService<br/>Async API Client]
            HTTPClient[HTTPClient<br/>Network Layer]
        end

        subgraph "Value Types"
            TestOp[TestOperation struct]
            SuiteOp[SuiteOperation struct]
        end

        subgraph "Utilities"
            Logger[Logger<br/>Correlation IDs]
            Metadata[MetadataCollector]
        end
    end

    subgraph "ReportPortal Server"
        API[ReportPortal API<br/>v1 REST]
    end

    XCTest -->|observe| RPListener
    RPListener -->|coordinate| LaunchMgr
    RPListener -->|track| OpTracker
    RPListener -->|report| ReportSvc
    ReportSvc -->|http| HTTPClient
    HTTPClient -->|async calls| API
    OpTracker -.->|store| TestOp
    OpTracker -.->|store| SuiteOp
    RPListener -->|log| Logger
    RPListener -->|collect| Metadata

    style LaunchMgr fill:#e1f5ff
    style OpTracker fill:#e1f5ff
    style TestOp fill:#fff4e6
    style SuiteOp fill:#fff4e6
```

### Data Flow Architecture

```mermaid
flowchart LR
    subgraph "Test Execution"
        T1[Test Bundle 1]
        T2[Test Bundle 2]
        T3[Test Bundle N]
    end

    subgraph "Agent Core"
        direction TB
        L[RPListener]
        LM[LaunchManager<br/>Actor]
        OT[OperationTracker<br/>Actor]
    end

    subgraph "ReportPortal"
        API[ReportPortal<br/>API]
    end

    T1 -.->|concurrent| L
    T2 -.->|concurrent| L
    T3 -.->|concurrent| L

    L -->|await| LM
    L -->|await| OT
    L -->|async| API

    LM -->|shared state| API
    OT -->|isolated state| API

    style LM fill:#e1f5ff
    style OT fill:#e1f5ff
```

---

## Component Design

### Core Components

#### 1. RPListener (Observer)

**Responsibility**: Observes XCTest lifecycle events and coordinates reporting.

**Type**: `class` (must conform to NSObject for XCTestObservation)

**Key Methods**:
- `testBundleWillStart(_:)` - Increments bundle count, creates/awaits launch
- `testSuiteWillStart(_:)` - Registers suite operation, starts suite in RP
- `testCaseWillStart(_:)` - Registers test operation, starts test in RP
- `testCaseDidFinish(_:)` - Updates test status, finishes test in RP
- `testSuiteDidFinish(_:)` - Finishes suite in RP
- `testBundleDidFinish(_:)` - Decrements bundle count, finalizes launch if zero

**Concurrency**: Spawns detached Tasks for async operations (XCTest callbacks are synchronous)

#### 2. LaunchManager (Actor)

**Responsibility**: Thread-safe launch-level state coordination.

**Type**: `actor` (singleton)

**State**:
```swift
private var launchID: String?
private var launchCreationTask: Task<String, Error>?
private var activeBundleCount: Int = 0
private var aggregatedStatus: TestStatus = .passed
private var isFinalized: Bool = false
```

**Key Methods**:
- `getOrAwaitLaunchID(launchTask:)` - Atomic launch creation coordination
- `incrementBundleCount()` - Thread-safe reference counting
- `decrementBundleCount() -> Bool` - Returns true when count reaches zero
- `updateStatus(_:)` - Aggregate worst status across all tests

**Concurrency**: Actor isolation ensures all methods are serialized

#### 3. OperationTracker (Actor)

**Responsibility**: Registry of active test/suite operations for concurrent access.

**Type**: `actor` (singleton)

**State**:
```swift
private var testOperations: [String: TestOperation] = [:]
private var suiteOperations: [String: SuiteOperation] = [:]
```

**Key Methods**:
- `registerTest(_:identifier:)` - Add test to registry
- `getTest(identifier:)` - Retrieve test operation
- `updateTest(_:identifier:)` - Update test state
- `unregisterTest(identifier:)` - Remove completed test (cleanup)
- Similar methods for suite operations

**Concurrency**: Actor isolation prevents concurrent dictionary mutations

#### 4. ReportingService (Stateless Service)

**Responsibility**: Async API client for ReportPortal operations.

**Type**: `class` (stateless, no instance variables)

**Key Methods**:
```swift
func startLaunch(name:tags:attributes:) async throws -> String
func finalizeLaunch(status:) async throws
func startSuite(operation:launchID:) async throws -> String
func finishSuite(operation:) async throws
func startTest(operation:launchID:) async throws -> String
func finishTest(operation:) async throws
func postLog(message:level:) async throws
```

**Concurrency**: All methods are `async`, no blocking operations

#### 5. TestOperation & SuiteOperation (Value Types)

**Responsibility**: Immutable context for test/suite execution.

**Type**: `struct` (value semantics)

**TestOperation Fields**:
```swift
let correlationID: UUID        // For log tracing
var testID: String             // ReportPortal test ID
let suiteID: String            // Parent suite ID
let testName: String
let className: String
var status: TestStatus
let startTime: Date
let metadata: [String: String]
var attachments: [Data]
```

**Concurrency**: Value types are inherently thread-safe (copied on assignment)

---

## Concurrency Model

### Actor Isolation Model

```mermaid
graph TB
    subgraph "Non-Isolated (Concurrent)"
        B1[Bundle 1 Task]
        B2[Bundle 2 Task]
        B3[Bundle N Task]

        T1[Test 1 Task]
        T2[Test 2 Task]
        T3[Test N Task]
    end

    subgraph "Actor-Isolated (Serialized)"
        LM[LaunchManager Actor<br/>Serial Execution Queue]
        OT[OperationTracker Actor<br/>Serial Execution Queue]
    end

    subgraph "ReportPortal API (Concurrent)"
        API1[API Call 1]
        API2[API Call 2]
        API3[API Call N]
    end

    B1 -->|await| LM
    B2 -->|await| LM
    B3 -->|await| LM

    T1 -->|await| OT
    T2 -->|await| OT
    T3 -->|await| OT

    B1 -.->|concurrent| API1
    T1 -.->|concurrent| API2
    T2 -.->|concurrent| API3

    LM -.->|state reads| B1
    LM -.->|state reads| B2

    style LM fill:#e1f5ff
    style OT fill:#e1f5ff
```

### Task Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: Task created by caller
    Created --> Passed: Passed to Actor
    Passed --> Evaluated: Actor checks state

    Evaluated --> Used: No existing task
    Evaluated --> Cancelled: Existing task found

    Used --> Stored: Store in actor
    Stored --> Executing: await task.value
    Executing --> Completed: Success
    Executing --> Failed: Error thrown

    Cancelled --> [*]: Task cleaned up
    Completed --> [*]: Result returned
    Failed --> Cleared: Clear stored task
    Cleared --> [*]: Allow retry
```

---

## Sequence Diagrams

### 1. Launch Creation (Race Condition Handling)

```mermaid
sequenceDiagram
    participant B1 as Bundle 1
    participant B2 as Bundle 2
    participant LM as LaunchManager Actor
    participant RS as ReportingService
    participant RP as ReportPortal API

    Note over B1,B2: Both bundles start simultaneously

    B1->>LM: incrementBundleCount()
    activate LM
    LM-->>B1: ✓ count=1
    deactivate LM

    B2->>LM: incrementBundleCount()
    activate LM
    LM-->>B2: ✓ count=2
    deactivate LM

    Note over B1: Creates launch task
    B1->>B1: Task { startLaunch(...) }

    Note over B2: Creates launch task
    B2->>B2: Task { startLaunch(...) }

    B1->>LM: getOrAwaitLaunchID(task1)
    activate LM
    Note over LM: No existing launch<br/>No existing task
    LM->>LM: Store task1
    LM->>RS: await task1.value
    deactivate LM

    B2->>LM: getOrAwaitLaunchID(task2)
    activate LM
    Note over LM: task1 exists!
    LM->>B2: Cancel task2
    LM->>LM: await task1.value
    deactivate LM

    RS->>RP: POST /launch
    RP-->>RS: { "id": "abc123" }
    RS-->>LM: "abc123"

    LM->>LM: launchID = "abc123"
    LM-->>B1: "abc123" ✓
    LM-->>B2: "abc123" ✓

    Note over B1,B2: Both bundles get same launch ID<br/>Only ONE API call made
```

### 2. Parallel Test Execution Flow

```mermaid
sequenceDiagram
    participant T1 as Test 1 (Thread A)
    participant T2 as Test 2 (Thread B)
    participant OT as OperationTracker Actor
    participant LM as LaunchManager Actor
    participant RS as ReportingService
    participant RP as ReportPortal API

    Note over T1,T2: Tests start in parallel

    par Test 1 Execution
        T1->>LM: await getLaunchID()
        LM-->>T1: "abc123"

        T1->>T1: Create TestOperation<br/>correlationID: uuid-1
        T1->>OT: registerTest(op1, "Class.test1")
        OT-->>T1: ✓ Registered

        T1->>RS: startTest(op1, "abc123")
        RS->>RP: POST /item (test)
        RP-->>RS: { "id": "test-001" }
        RS-->>T1: "test-001"

        T1->>OT: updateTest(op1, testID="test-001")
        OT-->>T1: ✓ Updated

        Note over T1: Test executes...

        T1->>T1: Update status = .passed
        T1->>OT: getTest("Class.test1")
        OT-->>T1: op1 (with testID)

        T1->>RS: finishTest(op1)
        RS->>RP: PUT /item/test-001 (finish)
        RP-->>RS: ✓ Finished
        RS-->>T1: ✓

        T1->>LM: updateStatus(.passed)
        T1->>OT: unregisterTest("Class.test1")
    and Test 2 Execution (Parallel)
        T2->>LM: await getLaunchID()
        LM-->>T2: "abc123"

        T2->>T2: Create TestOperation<br/>correlationID: uuid-2
        T2->>OT: registerTest(op2, "Class.test2")
        OT-->>T2: ✓ Registered

        T2->>RS: startTest(op2, "abc123")
        RS->>RP: POST /item (test)
        RP-->>RS: { "id": "test-002" }
        RS-->>T2: "test-002"

        T2->>OT: updateTest(op2, testID="test-002")
        OT-->>T2: ✓ Updated

        Note over T2: Test executes...

        T2->>T2: Update status = .failed
        T2->>OT: getTest("Class.test2")
        OT-->>T2: op2 (with testID)

        T2->>RS: finishTest(op2)
        RS->>RP: PUT /item/test-002 (finish)
        RP-->>RS: ✓ Finished
        RS-->>T2: ✓

        T2->>LM: updateStatus(.failed)
        T2->>OT: unregisterTest("Class.test2")
    end

    Note over LM: Aggregated status = .failed<br/>(worst status wins)
```

### 3. Launch Finalization (Reference Counting)

```mermaid
sequenceDiagram
    participant B1 as Bundle 1
    participant B2 as Bundle 2
    participant B3 as Bundle 3
    participant LM as LaunchManager Actor
    participant RS as ReportingService
    participant RP as ReportPortal API

    Note over B1,B2,B3: All bundles start
    B1->>LM: incrementBundleCount()
    LM->>LM: count = 1

    B2->>LM: incrementBundleCount()
    LM->>LM: count = 2

    B3->>LM: incrementBundleCount()
    LM->>LM: count = 3

    Note over B1,B2,B3: Tests execute...<br/>(order-independent)

    Note over B2: Bundle 2 finishes first
    B2->>LM: decrementBundleCount()
    activate LM
    LM->>LM: count = 2
    LM-->>B2: false (not zero)
    deactivate LM
    Note over B2: No finalization

    Note over B3: Bundle 3 finishes second
    B3->>LM: decrementBundleCount()
    activate LM
    LM->>LM: count = 1
    LM-->>B3: false (not zero)
    deactivate LM
    Note over B3: No finalization

    Note over B1: Bundle 1 finishes last
    B1->>LM: decrementBundleCount()
    activate LM
    LM->>LM: count = 0
    LM-->>B1: true (finalize!)
    deactivate LM

    B1->>LM: getAggregatedStatus()
    LM-->>B1: .failed

    B1->>LM: markFinalized()

    B1->>RS: finalizeLaunch(status: .failed)
    RS->>RP: PUT /launch/abc123 (finish)
    RP-->>RS: ✓ Finished
    RS-->>B1: ✓

    Note over B1: Launch finalized<br/>exactly once!
```

### 4. Error Handling Flow

```mermaid
sequenceDiagram
    participant T as Test
    participant LM as LaunchManager
    participant RS as ReportingService
    participant RP as ReportPortal API
    participant L as Logger

    Note over T: Test execution starts

    T->>LM: await getLaunchID()
    LM->>LM: Check launchID
    alt Launch exists
        LM-->>T: "abc123" ✓
    else Launch not ready
        LM-->>T: nil
        T->>L: error("Launch ID not available")
        Note over T: Test skips reporting<br/>but continues execution
    end

    T->>RS: startTest(...)
    RS->>RP: POST /item

    alt API Success
        RP-->>RS: { "id": "test-001" }
        RS-->>T: "test-001" ✓
    else Network Error
        RP--xRS: Error -1005 (connection lost)
        RS-->>T: throw NetworkError
        T->>L: error("Failed to start test", correlationID)
        Note over T: Error logged<br/>Test continues<br/>Other tests unaffected
    end

    Note over T: Test executes (isolated)

    T->>RS: finishTest(...)
    RS->>RP: PUT /item/test-001

    alt API Success
        RP-->>RS: ✓ Finished
        RS-->>T: ✓
        T->>L: info("Test finished", correlationID)
    else Launch ID Missing
        RS-->>T: throw LaunchIDNotFoundError
        T->>L: error("Failed to finish test: Launch ID not found")
        Note over T: Error isolated<br/>to this test only
    end
```

---

## State Management

### LaunchManager State Transitions

```mermaid
stateDiagram-v2
    [*] --> Idle: Agent initialized

    Idle --> CreatingLaunch: First bundle starts<br/>getOrAwaitLaunchID()

    CreatingLaunch --> LaunchReady: API call succeeds<br/>launchID set
    CreatingLaunch --> LaunchFailed: API call fails<br/>task cleared

    LaunchFailed --> CreatingLaunch: Retry by another bundle

    LaunchReady --> Executing: Tests running<br/>activeBundleCount > 0

    Executing --> Executing: Tests complete<br/>updateStatus()

    Executing --> Finalizing: Last bundle finishes<br/>count reaches 0

    Finalizing --> Finalized: finalizeLaunch() succeeds
    Finalizing --> FinalizeFailed: finalizeLaunch() fails

    Finalized --> [*]: Agent done
    FinalizeFailed --> [*]: Agent done (with errors)
```

### TestOperation Lifecycle

```mermaid
stateDiagram-v2
    [*] --> Created: TestOperation struct created

    Created --> Registered: registerTest() in OperationTracker

    Registered --> Starting: startTest() API call

    Starting --> Started: API returns testID<br/>updateTest() with ID
    Starting --> StartFailed: API error<br/>Operation may be unregistered

    Started --> Executing: Test runs

    Executing --> Updating: Test status changes<br/>(passed/failed/skipped)

    Updating --> Finishing: finishTest() API call

    Finishing --> Finished: API succeeds
    Finishing --> FinishFailed: API error

    Finished --> Unregistered: unregisterTest() cleanup
    StartFailed --> Unregistered: Cleanup
    FinishFailed --> Unregistered: Cleanup

    Unregistered --> [*]: Memory freed
```

---

## Design Rationale

### Why Actor-Based Concurrency?

**Problem**: Traditional locks (NSLock, DispatchQueue) require manual synchronization and are error-prone in concurrent code.

**Solution**: Swift Actors provide:
- **Compile-time safety**: Data races caught at compile time
- **Automatic synchronization**: Runtime handles locking
- **Deadlock prevention**: Actor reentrancy prevents self-deadlock
- **Clear isolation boundaries**: `await` makes async points explicit

**Trade-off**: All actor calls require `await`, adding suspension points. Acceptable because network operations already suspend.

### Why Task Sharing Over Closures?

**Problem**: Original design used `@escaping () async throws -> String` closure, mixing old-school escaping semantics with modern async/await.

**Solution**: Pass `Task<String, Error>` directly:
```swift
// Caller creates task
let task = Task { try await createLaunch() }

// Actor decides: use it, cancel it, or await existing
await actor.getOrAwaitLaunchID(launchTask: task)
```

**Benefits**:
- No `@escaping` needed (cleaner API)
- Task ownership explicit
- Easier cancellation (unused tasks cancelled explicitly)
- Idiomatic structured concurrency

### Why Reference Counting Over "Final Bundle" Flag?

**Problem**: v3.x used `IsFinalTestBundle` flag in Info.plist to determine which bundle should finalize launch. This breaks with parallel execution where bundle order is non-deterministic.

**Solution**: Reference counting:
```swift
// Each bundle increments on start
await launchManager.incrementBundleCount()

// Each bundle decrements on finish
let shouldFinalize = await launchManager.decrementBundleCount()
if shouldFinalize {
    // Last bundle out finalizes launch
}
```

**Benefits**:
- **Order-independent**: Works regardless of which bundle finishes first
- **Automatic**: No manual configuration needed
- **Race-free**: Actor serialization prevents concurrent decrements
- **Resilient**: Handles bundle crashes (timeout mechanism can be added)

### Why Value Types for Operations?

**Problem**: Reference types (classes) for test operations could be accidentally shared across threads.

**Solution**: Structs are value types:
```swift
struct TestOperation {
    let correlationID: UUID
    var testID: String
    var status: TestStatus
    // ...
}
```

**Benefits**:
- **Copy semantics**: Each thread gets independent copy
- **No shared state**: Impossible to accidentally mutate shared instance
- **Simpler reasoning**: No need to track references
- **Thread-safe by default**: Value types are inherently thread-safe

**Trade-off**: Mutations require explicit copy-modify-store pattern via OperationTracker. Acceptable because updates are infrequent and isolated.

### Why Detached Tasks in RPListener?

**Problem**: XCTest observation methods (`testCaseWillStart`, etc.) are synchronous callbacks. Cannot use `await` directly.

**Solution**: Spawn detached tasks:
```swift
public func testCaseWillStart(_ testCase: XCTestCase) {
    Task.detached(priority: .high) {
        // Async work here
        await launchManager.incrementBundleCount()
    }
}
```

**Benefits**:
- **Non-blocking**: XCTest doesn't wait for reporting
- **High priority**: Ensures launch creation starts immediately
- **Detached context**: Doesn't inherit caller's context (important for concurrency)

**Trade-off**: Fire-and-forget means test may complete before reporting finishes. Mitigated by `waitForLaunchID()` polling in dependent operations.

### Why Correlation IDs in Logs?

**Problem**: With parallel execution, logs from different tests interleave. Hard to trace which log belongs to which test.

**Solution**: Every TestOperation/SuiteOperation has a `correlationID: UUID`:
```swift
Logger.shared.info("Test started: \(testID)", correlationID: correlationID)
```

**Output**:
```
[2025-10-27T10:05:30Z] [Thread-A] [F3EB206A] [INFO] Test started: test-001
[2025-10-27T10:05:30Z] [Thread-B] [8D3AA1D0] [INFO] Test started: test-002
```

**Benefits**:
- **Traceability**: Can filter logs by correlation ID to see single test's lifecycle
- **Debugging**: Essential for diagnosing race conditions and timing issues
- **Observability**: Enables distributed tracing patterns in CI/CD

---

## Performance Characteristics

### Time Complexity

| Operation | Complexity | Notes |
|-----------|-----------|-------|
| Launch creation (first bundle) | O(1) | Single API call + actor state update |
| Launch creation (subsequent bundles) | O(1) | Await existing task (no API call) |
| Test registration | O(1) | Dictionary insert in OperationTracker |
| Test lookup | O(1) | Dictionary lookup by identifier |
| Status aggregation | O(1) | Simple comparison in LaunchManager |
| Bundle count increment/decrement | O(1) | Atomic integer operation |

### Space Complexity

| Component | Space | Notes |
|-----------|-------|-------|
| LaunchManager | O(1) | Fixed-size state (launch ID, counters, status) |
| OperationTracker | O(n) | n = active tests (cleared on completion) |
| TestOperation | O(1) | Fixed-size struct per test |
| Task storage | O(1) | Single shared Task<String, Error> |

### Scalability Limits

- **Maximum concurrent operations**: 10 (validated with OperationTracker warning)
- **Maximum bundle count**: Unlimited (reference counting handles any count)
- **Memory per test**: ~500 bytes (TestOperation struct + metadata)
- **Network concurrency**: URLSession connection pool (default 6 per host)

---

## Testing Strategy

### Unit Testing

Not applicable - Swift Actors and Tasks cannot be easily mocked. Integration testing is primary strategy.

### Integration Testing

See `ExampleUITests/` for comprehensive test coverage:
- `ParallelUITests_Calculations.swift` - 30+ tests (math operations)
- `ParallelUITests_Stress.swift` - 50+ tests (load testing)
- `PerformanceBenchmark.swift` - Sequential vs parallel timing

**Validation**:
- Thread Sanitizer (zero data races)
- Performance metrics (60-75% speedup)
- ReportPortal hierarchy verification

---

## Future Enhancements

### Potential Improvements

1. **Retry Logic for Launch Creation**
   - Current: Single attempt, logs error on failure
   - Future: Exponential backoff retry (3 attempts) before failing

2. **Timeout for Hung Bundles**
   - Current: Reference count may never reach zero if bundle crashes
   - Future: Timeout-based finalization (30 minutes default, configurable)

3. **Metrics Collection**
   - Current: Logs only
   - Future: Emit metrics (test count, duration, API latency) for observability

4. **Configurable Concurrency Limits**
   - Current: Hard-coded 10 concurrent operations warning
   - Future: User-configurable limit via Info.plist

5. **Launch Reuse Across Test Sessions**
   - Current: One launch per test session
   - Future: Reuse launch for multiple consecutive test runs (CI optimization)

---

## Glossary

| Term | Definition |
|------|------------|
| **Actor** | Swift Concurrency primitive providing thread-safe mutable state isolation |
| **Correlation ID** | UUID uniquely identifying a test operation across all log entries |
| **Launch** | Top-level test execution container in ReportPortal (contains suites) |
| **Operation** | Isolated execution context (TestOperation or SuiteOperation) |
| **Reference Counting** | Coordination mechanism tracking active bundle count for finalization |
| **Structured Concurrency** | Swift pattern where Task ownership and cancellation are explicit |
| **Task Sharing** | Pattern where multiple callers await the same Task instance |
| **Value Semantics** | Property where assignment creates independent copy (struct behavior) |

---

## References

- [Swift Concurrency Documentation](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [ReportPortal API v1 Specification](https://reportportal.io/docs/API-Documentation)
- [XCTest Framework Reference](https://developer.apple.com/documentation/xctest)
- [Swift Actors Proposal SE-0306](https://github.com/apple/swift-evolution/blob/main/proposals/0306-actors.md)

---

**Document Version**: 1.0
**Authors**: ReportPortal Team
**Last Review**: 2025-10-27
