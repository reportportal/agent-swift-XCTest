# OperationTracker Actor Contract

**Entity**: OperationTracker (Actor)  
**Purpose**: Thread-safe registry for active test and suite operations  
**Feature**: 001-parallel-execution

## Actor Declaration

```swift
actor OperationTracker {
    static let shared: OperationTracker
}
```

## State Properties

```swift
private var testOperations: [String: TestOperation]
private var suiteOperations: [String: SuiteOperation]
```

## Public API Methods

### Test Operation Management

```swift
func registerTest(_ operation: TestOperation, identifier: String)
```
**Purpose**: Register a test operation at test start  
**Parameters**:
- `operation`: TestOperation struct with correlation ID, test ID, metadata
- `identifier`: Unique XCTest identifier (format: "Bundle.Class.testMethod")

**Called From**: `RPListener.testCaseWillStart(_:)` after creating TestOperation  
**Thread Safety**: Actor-isolated write to dictionary  
**Side Effects**: Adds operation to `testOperations` dictionary  
**Precondition**: `identifier` should not already exist (new test)

---

```swift
func getTest(identifier: String) -> TestOperation?
```
**Purpose**: Retrieve test operation for given identifier  
**Parameters**: `identifier` - XCTest identifier  
**Returns**: TestOperation if found, `nil` if not registered  
**Called From**: `RPListener.testCaseDidFinish(_:)` to get operation for reporting  
**Thread Safety**: Actor-isolated read

---

```swift
func updateTest(_ operation: TestOperation, identifier: String)
```
**Purpose**: Update existing test operation (e.g., status change, add attachment)  
**Parameters**:
- `operation`: Updated TestOperation struct
- `identifier`: XCTest identifier

**Called From**: During test execution when status or attachments change  
**Thread Safety**: Actor-isolated write  
**Pattern**: Retrieve → Modify (create new struct) → Update

---

```swift
func unregisterTest(identifier: String)
```
**Purpose**: Remove test operation after reporting complete  
**Parameters**: `identifier` - XCTest identifier  
**Called From**: `RPListener.testCaseDidFinish(_:)` after successful reporting  
**Side Effects**: Removes entry from `testOperations` dictionary  
**Memory**: Prevents leaks by cleaning up completed tests

### Suite Operation Management

```swift
func registerSuite(_ operation: SuiteOperation, identifier: String)
```
**Purpose**: Register a suite operation at suite start  
**Parameters**:
- `operation`: SuiteOperation struct with correlation ID, suite ID, metadata
- `identifier`: Unique XCTest suite identifier (format: "Bundle.Class")

**Called From**: `RPListener.testSuiteWillStart(_:)` after creating SuiteOperation  
**Thread Safety**: Actor-isolated write  
**Side Effects**: Adds operation to `suiteOperations` dictionary

---

```swift
func getSuite(identifier: String) -> SuiteOperation?
```
**Purpose**: Retrieve suite operation for given identifier  
**Parameters**: `identifier` - XCTest suite identifier  
**Returns**: SuiteOperation if found, `nil` if not registered  
**Called From**: `RPListener.testSuiteDidFinish(_:)` to get operation for reporting  
**Thread Safety**: Actor-isolated read

---

```swift
func updateSuite(_ operation: SuiteOperation, identifier: String)
```
**Purpose**: Update existing suite operation (e.g., add child test, update status)  
**Parameters**:
- `operation`: Updated SuiteOperation struct
- `identifier`: XCTest suite identifier

**Called From**: When child tests complete (update aggregated status)  
**Thread Safety**: Actor-isolated write

---

```swift
func unregisterSuite(identifier: String)
```
**Purpose**: Remove suite operation after reporting complete  
**Parameters**: `identifier` - XCTest suite identifier  
**Called From**: `RPListener.testSuiteDidFinish(_:)` after successful reporting  
**Side Effects**: Removes entry from `suiteOperations` dictionary

### Diagnostics

```swift
func getActiveTestCount() -> Int
```
**Purpose**: Get count of currently active (registered) test operations  
**Returns**: Number of entries in `testOperations` dictionary  
**Use Case**: Logging, debugging, monitoring  
**Thread Safety**: Actor-isolated read

---

```swift
func getActiveSuiteCount() -> Int
```
**Purpose**: Get count of currently active (registered) suite operations  
**Returns**: Number of entries in `suiteOperations` dictionary  
**Use Case**: Logging, debugging, monitoring

---

```swift
func getAllTestIdentifiers() -> [String]
```
**Purpose**: Get all active test identifiers (for debugging)  
**Returns**: Array of test identifier strings  
**Use Case**: Diagnostics, verifying cleanup

---

```swift
func reset()
```
**Purpose**: Clear all operations (for testing or launch cleanup)  
**Called From**: After launch finalization or in unit tests  
**Side Effects**: 
- Clears `testOperations` dictionary
- Clears `suiteOperations` dictionary

## Usage Example

```swift
// In RPListener
class RPListener: NSObject, XCTestObservation {
    private let tracker = OperationTracker.shared
    
    func testCaseWillStart(_ testCase: XCTestCase) {
        Task {
            let identifier = testCase.name // e.g., "MyTestCase.testExample"
            
            // Create operation
            let operation = TestOperation(
                correlationID: UUID(),
                testID: "", // Will be set after API call
                suiteID: suiteID,
                testName: testCase.name,
                className: String(describing: type(of: testCase)),
                status: .inProgress,
                startTime: Date(),
                metadata: collectMetadata(),
                attachments: []
            )
            
            // Register
            await tracker.registerTest(operation, identifier: identifier)
            
            // Start test in ReportPortal
            let testID = try await reportingService.startTest(operation)
            
            // Update with test ID
            var updated = operation
            updated.testID = testID
            await tracker.updateTest(updated, identifier: identifier)
        }
    }
    
    func testCaseDidFinish(_ testCase: XCTestCase) {
        Task {
            let identifier = testCase.name
            
            // Retrieve operation
            guard var operation = await tracker.getTest(identifier: identifier) else {
                Logger.shared.error("Operation not found: \(identifier)")
                return
            }
            
            // Update status
            operation.status = testCase.testRun?.hasSucceeded == true ? .passed : .failed
            
            // Report to ReportPortal
            try await reportingService.finishTest(operation)
            
            // Unregister (cleanup)
            await tracker.unregisterTest(identifier: identifier)
            
            Logger.shared.info("Test completed", correlationID: operation.correlationID)
        }
    }
}
```

## Identifier Format

### Test Identifiers
- Format: `"{BundleID}.{ClassName}.{testMethodName}"`
- Example: `"MyAppTests.LoginTests.testSuccessfulLogin"`
- Uniqueness: Bundle + Class + Method ensures no collisions

### Suite Identifiers
- Format: `"{BundleID}.{ClassName}"` for class suites
- Format: `"{BundleID}"` for root (bundle) suites
- Example: `"MyAppTests.LoginTests"` or `"MyAppTests"`

## Concurrency Guarantees

1. **Actor Isolation**: Dictionary access is serialized (no concurrent modifications)
2. **Safe Retrieval**: Optional return prevents crashes if operation missing
3. **Memory Safety**: Unregister prevents memory leaks in long test runs
4. **No Lost Updates**: Actor ensures updates don't get lost due to race conditions

## Error Handling

- Methods don't throw (state management is fault-tolerant)
- Missing operations return `nil` (caller handles with guard/if-let)
- Duplicate registration overwrites (last-write-wins semantics)

## Performance Characteristics

- **Actor Method Overhead**: ~50-100ns per call
- **Dictionary Lookup**: O(1) average case
- **Memory**: ~200 bytes per TestOperation, ~150 bytes per SuiteOperation
- **Contention**: Low (different tests access different keys mostly)

## Memory Management

- **Registration**: O(n) space where n = concurrent operations
- **Unregistration**: Must happen after each test to prevent leaks
- **Reset**: Use sparingly (only for cleanup between launches or in tests)
- **Expected Size**: With 10 concurrent tests: ~2KB total
