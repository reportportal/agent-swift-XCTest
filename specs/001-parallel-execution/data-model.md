# Data Model: Parallel Test Execution Support

**Feature**: 001-parallel-execution  
**Phase**: 1 (Design & Contracts)  
**Date**: 2025-10-17

## Overview

This document defines the data entities and their relationships for parallel test execution support. The model uses Swift Concurrency primitives (Actor, struct) to ensure thread safety and state isolation.

## Entity Diagram

```
┌─────────────────────────────────────────────────────┐
│           LaunchManager (Actor)                     │
│  - launchID: String?                                │
│  - activeBundleCount: Int                           │
│  - aggregatedStatus: TestStatus                     │
│  - timeout: TimeInterval (30 min)                   │
│                                                     │
│  + incrementBundleCount()                           │
│  + decrementBundleCount() async -> Bool             │
│  + updateStatus(_ status: TestStatus) async         │
│  + getLaunchID() async -> String?                   │
└─────────────────────────────────────────────────────┘
                        ▲
                        │ shared singleton
                        │
┌─────────────────────────────────────────────────────┐
│        OperationTracker (Actor)                     │
│  - operations: [String: TestOperation]              │
│  - suiteOperations: [String: SuiteOperation]        │
│                                                     │
│  + register(_ op: TestOperation)                    │
│  + unregister(_ testID: String)                     │
│  + getOperation(_ testID: String) -> TestOperation? │
└─────────────────────────────────────────────────────┘
                        │
                        │ manages collection of
                        │
        ┌───────────────┴───────────────┐
        │                               │
        ▼                               ▼
┌─────────────────────┐      ┌─────────────────────┐
│  TestOperation      │      │  SuiteOperation     │
│  (struct)           │      │  (struct)           │
│                     │      │                     │
│  - correlationID    │      │  - correlationID    │
│  - testID           │      │  - suiteID          │
│  - suiteID          │      │  - rootSuiteID      │
│  - status           │      │  - status           │
│  - startTime        │      │  - childTests: []   │
│  - metadata         │      │  - startTime        │
└─────────────────────┘      └─────────────────────┘
```

## Entities

### 1. TestOperation (struct)

**Purpose**: Represents an isolated execution context for a single test case. Immutable value type ensures no shared state between concurrent tests.

**Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `correlationID` | `UUID` | Unique identifier for tracing this test's lifecycle across logs |
| `testID` | `String` | ReportPortal item ID for this test case (from StartItem response) |
| `suiteID` | `String` | Parent suite ID (for hierarchy) |
| `testName` | `String` | XCTest test method name (e.g., "testExample") |
| `className` | `String` | XCTest class name (e.g., "MyTestCase") |
| `status` | `TestStatus` | Current status (.inProgress, .passed, .failed, .skipped) |
| `startTime` | `Date` | Test start timestamp |
| `metadata` | `[String: String]` | Device info, test plan name, tags |
| `attachments` | `[XCTAttachment]` | Screenshots, logs collected during test |

**Lifecycle**:
1. Created in `testCaseWillStart(_:)` with correlation ID and metadata
2. Registered in OperationTracker
3. Updated during test execution (status changes, attachments added)
4. Retrieved in `testCaseDidFinish(_:)` for reporting
5. Unregistered after reporting complete

**Sendable Conformance**:
```swift
struct TestOperation: Sendable {
    let correlationID: UUID
    let testID: String
    let suiteID: String
    let testName: String
    let className: String
    var status: TestStatus
    let startTime: Date
    var metadata: [String: String]
    var attachments: [XCTAttachment]
}
```

**Immutability Strategy**:
- `let` for properties that never change (IDs, timestamps)
- `var` for properties that update (status, attachments), but updates are local within Task

---

### 2. SuiteOperation (struct)

**Purpose**: Represents a test suite execution context, managing hierarchy and child test relationships.

**Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `correlationID` | `UUID` | Unique identifier for this suite's lifecycle |
| `suiteID` | `String` | ReportPortal item ID for this suite |
| `rootSuiteID` | `String?` | Parent root suite ID (nil for root) |
| `suiteName` | `String` | XCTest suite name (e.g., "MyTestCase") |
| `status` | `TestStatus` | Aggregated status from child tests |
| `startTime` | `Date` | Suite start timestamp |
| `childTestIDs` | `[String]` | ReportPortal IDs of child test cases |
| `metadata` | `[String: String]` | Device info, bundle name |

**Hierarchy**:
```
RootSuite (Bundle)
  └── TestSuite (Class)
       ├── TestCase 1
       ├── TestCase 2
       └── TestCase 3
```

**Sendable Conformance**:
```swift
struct SuiteOperation: Sendable {
    let correlationID: UUID
    let suiteID: String
    let rootSuiteID: String?
    let suiteName: String
    var status: TestStatus
    let startTime: Date
    var childTestIDs: [String]
    var metadata: [String: String]
}
```

---

### 3. LaunchManager (Actor)

**Purpose**: Shared singleton managing launch-level state with thread-safe operations. Handles bundle reference counting and launch finalization.

**Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `launchID` | `String?` | ReportPortal launch ID (shared across all bundles) |
| `activeBundleCount` | `Int` | Number of active test bundles (for reference counting) |
| `aggregatedStatus` | `TestStatus` | Overall launch status (worst of all tests) |
| `finalizationTimeout` | `TimeInterval` | Max time before forced finalization (default 1800s / 30 min) |
| `launchStartTime` | `Date?` | Launch start timestamp |
| `isFinalized` | `Bool` | Whether launch has been finalized |

**Methods**:

```swift
actor LaunchManager {
    static let shared = LaunchManager()
    
    private var launchID: String?
    private var activeBundleCount: Int = 0
    private var aggregatedStatus: TestStatus = .passed
    private var isFinalized: Bool = false
    
    // Bundle lifecycle
    func incrementBundleCount() {
        activeBundleCount += 1
    }
    
    func decrementBundleCount() -> Bool {
        activeBundleCount -= 1
        return activeBundleCount == 0
    }
    
    func getActiveBundleCount() -> Int {
        return activeBundleCount
    }
    
    // Launch management
    func setLaunchID(_ id: String) {
        self.launchID = id
    }
    
    func getLaunchID() -> String? {
        return launchID
    }
    
    // Status aggregation (worst status wins)
    func updateStatus(_ newStatus: TestStatus) {
        if newStatus.severity > aggregatedStatus.severity {
            aggregatedStatus = newStatus
        }
    }
    
    func getAggregatedStatus() -> TestStatus {
        return aggregatedStatus
    }
    
    // Finalization
    func markFinalized() {
        isFinalized = true
    }
    
    func isLaunchFinalized() -> Bool {
        return isFinalized
    }
}
```

**Thread Safety**:
- Actor isolation ensures only one Task modifies state at a time
- All async methods automatically serialize access
- No manual locks or semaphores needed

**Singleton Pattern**:
- `static let shared` provides global access point
- Actor semantics replace traditional singleton locking

---

### 4. OperationTracker (Actor)

**Purpose**: Thread-safe registry mapping XCTest identifiers to operation contexts.

**Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `testOperations` | `[String: TestOperation]` | Active test operations (key: XCTest identifier) |
| `suiteOperations` | `[String: SuiteOperation]` | Active suite operations (key: suite identifier) |

**Methods**:

```swift
actor OperationTracker {
    static let shared = OperationTracker()
    
    private var testOperations: [String: TestOperation] = [:]
    private var suiteOperations: [String: SuiteOperation] = [:]
    
    // Test operations
    func registerTest(_ operation: TestOperation, identifier: String) {
        testOperations[identifier] = operation
    }
    
    func getTest(identifier: String) -> TestOperation? {
        return testOperations[identifier]
    }
    
    func updateTest(_ operation: TestOperation, identifier: String) {
        testOperations[identifier] = operation
    }
    
    func unregisterTest(identifier: String) {
        testOperations.removeValue(forKey: identifier)
    }
    
    // Suite operations
    func registerSuite(_ operation: SuiteOperation, identifier: String) {
        suiteOperations[identifier] = operation
    }
    
    func getSuite(identifier: String) -> SuiteOperation? {
        return suiteOperations[identifier]
    }
    
    func updateSuite(_ operation: SuiteOperation, identifier: String) {
        suiteOperations[identifier] = operation
    }
    
    func unregisterSuite(identifier: String) {
        suiteOperations.removeValue(forKey: identifier)
    }
    
    // Diagnostics
    func getActiveTestCount() -> Int {
        return testOperations.count
    }
    
    func getActiveSuiteCount() -> Int {
        return suiteOperations.count
    }
}
```

**Key Generation**:
- XCTest provides unique identifiers via test method names + class names
- Format: `"Bundle.ClassName.testMethodName"`
- Handles parallel tests with same name by including bundle identifier

---

### 5. Logger (struct)

**Purpose**: Structured logging utility with correlation ID support for debugging parallel execution.

**Properties**:

| Property | Type | Description |
|----------|------|-------------|
| `enabled` | `Bool` | Whether logging is enabled (from config or env var) |
| `minLevel` | `LogLevel` | Minimum log level to output |

**Log Levels**:

```swift
enum LogLevel: Int, Comparable {
    case debug = 0
    case info = 1
    case warning = 2
    case error = 3
    
    static func < (lhs: LogLevel, rhs: LogLevel) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}
```

**Methods**:

```swift
struct Logger {
    static let shared = Logger()
    
    func log(_ message: String, 
             level: LogLevel = .info,
             correlationID: UUID? = nil,
             file: String = #file,
             line: Int = #line) {
        guard enabled else { return }
        guard level >= minLevel else { return }
        
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let thread = Thread.current.name ?? Thread.current.description
        let fileName = (file as NSString).lastPathComponent
        
        var logMessage = "[\(timestamp)]"
        logMessage += " [\(thread)]"
        if let corID = correlationID {
            logMessage += " [\(corID.uuidString.prefix(8))]"
        }
        logMessage += " [\(level)]"
        logMessage += " [\(fileName):\(line)]"
        logMessage += " \(message)"
        
        print(logMessage)
    }
    
    func debug(_ message: String, correlationID: UUID? = nil) {
        log(message, level: .debug, correlationID: correlationID)
    }
    
    func info(_ message: String, correlationID: UUID? = nil) {
        log(message, level: .info, correlationID: correlationID)
    }
    
    func warning(_ message: String, correlationID: UUID? = nil) {
        log(message, level: .warning, correlationID: correlationID)
    }
    
    func error(_ message: String, correlationID: UUID? = nil) {
        log(message, level: .error, correlationID: correlationID)
    }
}
```

**Example Output**:
```
[2025-10-17T14:23:45Z] [Thread-3] [A1B2C3D4] [INFO] [RPListener.swift:120] Test started: MyTest.testExample
[2025-10-17T14:23:46Z] [Thread-3] [A1B2C3D4] [DEBUG] [ReportingService.swift:45] Reporting to RP: item ID 12345
[2025-10-17T14:23:47Z] [Thread-3] [A1B2C3D4] [INFO] [RPListener.swift:145] Test finished: passed
```

---

## State Transitions

### TestOperation Status Flow

```
.inProgress → .passed
            → .failed
            → .skipped
```

### Launch Status Aggregation (Worst Status Wins)

```
Priority: .failed > .skipped > .passed

Bundle 1: .passed
Bundle 2: .failed  } → Launch: .failed
Bundle 3: .passed
```

### Bundle Reference Counting

```
Initial: activeBundleCount = 0

Bundle 1 start: count++ → 1
Bundle 2 start: count++ → 2
Bundle 3 start: count++ → 3

Bundle 2 finish: count-- → 2
Bundle 1 finish: count-- → 1
Bundle 3 finish: count-- → 0 → FINALIZE LAUNCH
```

---

## Relationships

### Containment
- **LaunchManager** contains many **Bundles** (via reference count)
- **SuiteOperation** contains many **TestOperation** IDs (via childTestIDs)
- **OperationTracker** contains all active **TestOperation** and **SuiteOperation** instances

### Composition
- **TestOperation** has correlation ID, test ID, suite ID
- **SuiteOperation** has correlation ID, suite ID, root suite ID (parent)

### Association
- **TestOperation** → **LaunchManager**: Reports status for aggregation
- **TestOperation** → **OperationTracker**: Registered/unregistered for lifecycle tracking
- **SuiteOperation** → **OperationTracker**: Registered for hierarchy management

---

## Concurrency Model

### Value Types (Structs)
- **TestOperation**: Immutable data passed between Tasks
- **SuiteOperation**: Immutable data, updated by creating new copy
- **Logger**: Stateless utility (static shared instance OK)

### Reference Types (Actors)
- **LaunchManager**: Shared mutable state, protected by Actor
- **OperationTracker**: Shared registry, protected by Actor

### Sendable Compliance
All entities conform to `Sendable` for safe cross-actor communication:
- Structs are implicitly Sendable (value types)
- Actors are implicitly Sendable (isolated state)
- Collections (`[String: TestOperation]`) are Sendable if contents are Sendable

---

## Data Validation Rules

### TestOperation
- `correlationID`: Must be unique UUID (generated on creation)
- `testID`: Must be non-empty string from ReportPortal response
- `suiteID`: Must reference existing suite in OperationTracker
- `status`: Must be valid TestStatus enum value
- `startTime`: Must be ≤ current time
- `testName`, `className`: Must be non-empty (from XCTest)

### SuiteOperation
- `correlationID`: Must be unique UUID
- `suiteID`: Must be non-empty string from ReportPortal
- `suiteName`: Must be non-empty (from XCTest)
- `childTestIDs`: May be empty (populated as tests run)
- `rootSuiteID`: nil for root suite, otherwise valid suite ID

### LaunchManager
- `activeBundleCount`: Must be ≥ 0 (never negative)
- `launchID`: nil before launch starts, non-empty string after
- `aggregatedStatus`: Monotonic worsening (can't improve)

---

## Memory Management

### Lifecycle
- **TestOperation**: Created → Registered → Updated → Reported → Unregistered
- **SuiteOperation**: Created → Registered → Updated → Reported → Unregistered
- **Actors**: Singleton instances live for app lifetime

### Cleanup
- Operations must be unregistered after reporting to prevent memory leaks
- OperationTracker should be empty after all tests finish
- LaunchManager state resets after finalization (for next launch)

### Memory Estimates
- TestOperation: ~200 bytes
- SuiteOperation: ~150 bytes
- 10 concurrent operations: ~3.5KB total (negligible)
- Actor overhead: ~1KB per actor instance

---

## Next Steps

Proceed to create:
1. **contracts/** - API method signatures for entities
2. **quickstart.md** - Developer guide
3. **Update agent context** - Add Swift Concurrency guidance
