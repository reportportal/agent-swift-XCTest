# LaunchManager Actor Contract

**Entity**: LaunchManager (Actor)  
**Purpose**: Thread-safe launch-level state management with reference counting  
**Feature**: 001-parallel-execution

## Actor Declaration

```swift
actor LaunchManager {
    static let shared: LaunchManager
}
```

## State Properties

```swift
private var launchID: String?
private var activeBundleCount: Int
private var aggregatedStatus: TestStatus
private var isFinalized: Bool
private var launchStartTime: Date?
```

## Public API Methods

### Bundle Lifecycle

```swift
func incrementBundleCount()
```
**Purpose**: Increment active bundle counter when test bundle starts  
**Called From**: `RPListener.testBundleWillStart(_:)`  
**Thread Safety**: Actor-isolated, safe to call concurrently  
**Side Effects**: Increases `activeBundleCount` by 1

---

```swift
func decrementBundleCount() -> Bool
```
**Purpose**: Decrement active bundle counter when test bundle finishes  
**Returns**: `true` if count reached zero (should finalize launch), `false` otherwise  
**Called From**: `RPListener.testBundleDidFinish(_:)`  
**Thread Safety**: Actor-isolated, atomic decrement  
**Side Effects**: Decreases `activeBundleCount` by 1  
**Invariant**: `activeBundleCount >= 0` always

---

```swift
func getActiveBundleCount() -> Int
```
**Purpose**: Get current active bundle count (for diagnostics)  
**Returns**: Current value of `activeBundleCount`  
**Thread Safety**: Actor-isolated read

### Launch Management

```swift
func setLaunchID(_ id: String)
```
**Purpose**: Store ReportPortal launch ID after launch creation  
**Parameters**: `id` - Launch ID from StartLaunch API response  
**Called From**: `ReportingService` after successful launch start  
**Precondition**: `id` must be non-empty  
**Side Effects**: Sets `launchID` property

---

```swift
func getLaunchID() -> String?
```
**Purpose**: Retrieve current launch ID  
**Returns**: Launch ID if set, `nil` if launch not yet started  
**Called From**: `ReportingService` when starting items  
**Thread Safety**: Actor-isolated read

### Status Aggregation

```swift
func updateStatus(_ newStatus: TestStatus)
```
**Purpose**: Update aggregated launch status (worst status wins)  
**Parameters**: `newStatus` - Status from completed test  
**Logic**: If `newStatus` is worse than current, update to worse status  
**Status Priority**: `.failed` > `.skipped` > `.passed`  
**Called From**: `RPListener.testCaseDidFinish(_:)` after each test  
**Thread Safety**: Actor-isolated update  
**Monotonic**: Status can only worsen, never improve

---

```swift
func getAggregatedStatus() -> TestStatus
```
**Purpose**: Get current aggregated launch status  
**Returns**: Worst status seen across all completed tests  
**Called From**: `ReportingService` when finalizing launch  
**Default**: `.passed` if no tests failed or skipped

### Finalization

```swift
func markFinalized()
```
**Purpose**: Mark launch as finalized (prevent duplicate finalization)  
**Called From**: `ReportingService.finalizeLaunch()` after successful FinishLaunch API call  
**Side Effects**: Sets `isFinalized = true`  
**Idempotent**: Safe to call multiple times (no-op after first call)

---

```swift
func isLaunchFinalized() -> Bool
```
**Purpose**: Check if launch has been finalized  
**Returns**: `true` if finalized, `false` otherwise  
**Called From**: Bundle finish handler to prevent duplicate finalization  
**Use Case**: Guard against race condition where multiple bundles finish simultaneously

---

```swift
func reset()
```
**Purpose**: Reset state for next launch (if agent is reused)  
**Called From**: After successful launch finalization (optional cleanup)  
**Side Effects**: 
- Clears `launchID`
- Resets `activeBundleCount` to 0
- Resets `aggregatedStatus` to `.passed`
- Sets `isFinalized` to `false`

## Usage Example

```swift
// In RPListener
class RPListener: NSObject, XCTestObservation {
    private let launchManager = LaunchManager.shared
    
    func testBundleWillStart(_ testBundle: Bundle) {
        Task {
            await launchManager.incrementBundleCount()
            
            // Start launch if first bundle
            if await launchManager.getLaunchID() == nil {
                let launchID = try await startLaunch()
                await launchManager.setLaunchID(launchID)
            }
        }
    }
    
    func testBundleDidFinish(_ testBundle: Bundle) {
        Task {
            let shouldFinalize = await launchManager.decrementBundleCount()
            
            if shouldFinalize && !await launchManager.isLaunchFinalized() {
                let status = await launchManager.getAggregatedStatus()
                try await finalizeLaunch(status: status)
                await launchManager.markFinalized()
            }
        }
    }
    
    func testCaseDidFinish(_ testCase: XCTestCase) {
        Task {
            let status = testCase.testRun?.hasSucceeded == true ? .passed : .failed
            await launchManager.updateStatus(status)
        }
    }
}
```

## Concurrency Guarantees

1. **Actor Isolation**: All methods execute serially within actor's executor
2. **No Race Conditions**: Reference counting is atomic (increment/decrement never corrupted)
3. **Status Monotonicity**: Aggregated status can only worsen (thread-safe comparison)
4. **Finalization Safety**: `isFinalized` flag prevents duplicate FinishLaunch API calls

## Error Handling

- No throwing methods (state management doesn't fail)
- Caller responsible for handling API errors (LaunchManager is state-only)
- Invalid states (negative count) prevented by Actor isolation

## Performance Characteristics

- **Actor Method Overhead**: ~50-100ns per call (negligible)
- **Contention**: Low (10 concurrent bundles → minimal actor queue depth)
- **Memory**: Fixed size (~200 bytes for actor state)
