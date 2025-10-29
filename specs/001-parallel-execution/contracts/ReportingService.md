# ReportingService Async API Contract

**Entity**: ReportingService (Refactored)  
**Purpose**: Async/await API for ReportPortal communication  
**Feature**: 001-parallel-execution

## Class Declaration

```swift
public final class ReportingService {
    // Stateless - no instance variables (all state in LaunchManager/OperationTracker)
    private let httpClient: HTTPClient
    private let config: AgentConfiguration
    
    init(configuration: AgentConfiguration, httpClient: HTTPClient)
}
```

## API Methods (All Async)

### Launch Management

```swift
func startLaunch(name: String, tags: [String], attributes: [String: String]) async throws -> String
```
**Purpose**: Create new launch in ReportPortal  
**Parameters**:
- `name`: Launch name from config or test plan
- `tags`: Array of tags from config
- `attributes`: Metadata (device info, OS version, etc.)

**Returns**: Launch ID (UUID string from ReportPortal)  
**Throws**: `ReportingServiceError` if API call fails  
**Side Effects**: Sets launch ID in LaunchManager  
**Network**: POST to `/launch` endpoint  
**Async**: Non-blocking URLSession request

---

```swift
func finalizeLaunch(launchID: String, status: TestStatus) async throws
```
**Purpose**: Finish launch in ReportPortal  
**Parameters**:
- `launchID`: Launch ID from LaunchManager
- `status`: Aggregated status from LaunchManager

**Throws**: `ReportPortalError` if API call fails  
**Side Effects**: Marks launch as finalized in LaunchManager  
**Network**: PUT to `/launch/{launchID}/finish`  
**Idempotency**: Safe to retry (RP ignores duplicate finish)

### Item (Suite/Test) Management

```swift
func startSuite(operation: SuiteOperation, launchID: String) async throws -> String
```
**Purpose**: Create suite item in ReportPortal  
**Parameters**:
- `operation`: SuiteOperation with metadata
- `launchID`: Parent launch ID

**Returns**: Suite item ID (UUID string)  
**Throws**: `ReportPortalError` if API call fails  
**Network**: POST to `/item` with type "suite"  
**Logging**: Logs start event with correlation ID

---

```swift
func finishSuite(operation: SuiteOperation) async throws
```
**Purpose**: Finish suite item in ReportPortal  
**Parameters**: `operation` - SuiteOperation with suite ID and final status  
**Throws**: `ReportPortalError` if API call fails  
**Network**: PUT to `/item/{suiteID}/finish`

---

```swift
func startTest(operation: TestOperation, launchID: String) async throws -> String
```
**Purpose**: Create test item in ReportPortal  
**Parameters**:
- `operation`: TestOperation with metadata
- `launchID`: Parent launch ID

**Returns**: Test item ID (UUID string)  
**Throws**: `ReportPortalError` if API call fails  
**Network**: POST to `/item` with type "step"  
**Logging**: Logs test start with correlation ID

---

```swift
func finishTest(operation: TestOperation) async throws
```
**Purpose**: Finish test item in ReportPortal  
**Parameters**: `operation` - TestOperation with test ID and final status  
**Throws**: `ReportPortalError` if API call fails  
**Network**: PUT to `/item/{testID}/finish`  
**Logging**: Logs test completion with correlation ID

### Logging & Attachments

```swift
func postLog(message: String, level: LogLevel, itemID: String, time: Date) async throws
```
**Purpose**: Send log entry to ReportPortal  
**Parameters**:
- `message`: Log message text
- `level`: Log level (info, warn, error, etc.)
- `itemID`: Test or suite item ID
- `time`: Timestamp of log

**Throws**: `ReportPortalError` if API call fails  
**Network**: POST to `/log`  
**Async**: Non-blocking (doesn't delay test execution)

---

```swift
func postAttachment(attachment: XCTAttachment, itemID: String) async throws
```
**Purpose**: Upload attachment (screenshot, file) to ReportPortal  
**Parameters**:
- `attachment`: XCTAttachment from test
- `itemID`: Test item ID to attach to

**Throws**: `ReportPortalError` if upload fails  
**Network**: POST to `/log` with multipart/form-data  
**Async**: Non-blocking upload

## Error Handling

### Error Types

```swift
enum ReportPortalError: Error {
    case networkError(URLError)
    case apiError(statusCode: Int, message: String)
    case invalidResponse
    case timeout
    case unauthorized
    case itemNotFound(itemID: String)
}
```

### Retry Strategy

```swift
func executeWithRetry<T>(_ operation: () async throws -> T, 
                         maxRetries: Int = 3,
                         delay: TimeInterval = 1.0) async throws -> T
```
**Purpose**: Retry failed API calls with exponential backoff  
**Parameters**:
- `operation`: Async throwing closure to retry
- `maxRetries`: Maximum retry attempts (default 3)
- `delay`: Initial delay between retries (doubles each retry)

**Throws**: Last error if all retries fail  
**Use Case**: Network transient errors, server 5xx responses

## Usage Example

```swift
// In RPListener
func testCaseWillStart(_ testCase: XCTestCase) {
    Task {
        do {
            let launchID = await LaunchManager.shared.getLaunchID()
            
            // Create operation
            var operation = TestOperation(...)
            await OperationTracker.shared.registerTest(operation, identifier: testCase.name)
            
            // Start test in RP (async, non-blocking)
            let testID = try await reportingService.startTest(
                operation: operation,
                launchID: launchID ?? ""
            )
            
            // Update operation with test ID
            operation.testID = testID
            await OperationTracker.shared.updateTest(operation, identifier: testCase.name)
            
            Logger.shared.info("Test started: \(testID)", correlationID: operation.correlationID)
        } catch {
            // Log error but don't crash test execution
            Logger.shared.error("Failed to start test: \(error)")
        }
    }
}
```

## Concurrency Patterns

### Non-Blocking Operations
- All methods use `async` instead of blocking with semaphores
- URLSession async methods release thread while waiting for network
- No `DispatchSemaphore` (eliminates priority inversion)

### Task-Based Execution
- XCTest observation methods spawn detached Tasks
- Tasks run concurrently on cooperative thread pool
- Structured concurrency ensures proper cleanup

### Actor Integration
```swift
func startTest(operation: TestOperation, launchID: String) async throws -> String {
    // Network I/O (async, non-blocking)
    let itemID = try await httpClient.postItem(...)
    
    // Update actor state (actor-isolated)
    await LaunchManager.shared.updateStatus(operation.status)
    
    // Log with correlation ID
    Logger.shared.info("Started test: \(itemID)", correlationID: operation.correlationID)
    
    return itemID
}
```

## Performance Characteristics

### Latency
- Async operations don't block test execution
- Tests continue while network requests in flight
- Parallel tests make parallel API calls

### Throughput
- 10 concurrent tests → up to 10 concurrent HTTP requests
- URLSession connection pooling reuses connections
- HTTP/2 multiplexing over single connection

### Resource Usage
- No thread blocking → threads available for other work
- Cooperative thread pool (Swift runtime manages)
- Memory: O(concurrent requests) for in-flight buffers

## Migration from Blocking to Async

### Before (Blocking with Semaphore)
```swift
func startItem(_ item: Item) -> String? {
    let semaphore = DispatchSemaphore(value: 0)
    var itemID: String?
    
    httpClient.post(item) { response in
        itemID = response.id
        semaphore.signal()
    }
    
    semaphore.wait(timeout: .now() + 10)  // BLOCKS THREAD FOR UP TO 10s
    return itemID
}
```

### After (Non-Blocking Async)
```swift
func startItem(_ item: Item) async throws -> String {
    let response = try await httpClient.post(item)  // SUSPENDS, DOESN'T BLOCK
    return response.id
}
```

## Thread Safety

- **No Shared Mutable State**: ReportingService is stateless (all state in Actors)
- **Safe Concurrent Calls**: Multiple tests can call methods concurrently
- **Actor Coordination**: Status updates go through LaunchManager (actor-isolated)
- **No Locks Needed**: Async/await + Actor model eliminate need for manual synchronization
