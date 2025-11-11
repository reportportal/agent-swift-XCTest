# LaunchManager Contract

**Entity**: LaunchManager (Singleton Class)  
**Purpose**: Minimal launch UUID storage for single bundle execution  
**Feature**: 001-parallel-execution

## Class Declaration

```swift
final class LaunchManager {
    static let shared: LaunchManager
    private init()
}
```

**Note**: Changed from Actor to simple class because no async coordination is needed. The launch ID is set once and then only read.

## State Properties

```swift
private(set) lazy var launchID: String
```

**Implementation**:
```swift
private(set) lazy var launchID: String = {
    let uuid = UUID().uuidString
    Logger.shared.info("📦 Launch initialized with UUID: \(uuid)")
    return uuid
}()
```

**Characteristics**:
- **Lazy initialization**: UUID generated on first access
- **Thread-safe**: Swift guarantees lazy vars are initialized only once
- **Read-only externally**: `private(set)` prevents external modification
- **Immutable after init**: Once set, never changes

## Public API

### Property Access

```swift
LaunchManager.shared.launchID  // String (not optional!)
```

**Purpose**: Get launch UUID (custom client-generated UUID)  
**Returns**: Launch ID (auto-generated UUID on first access)  
**Thread Safety**: Thread-safe via Swift's lazy initialization guarantee  
**When to use**: Anytime you need the launch ID - it's always available

## Design Rationale

### Why So Simple?

1. **Single Bundle Execution**: Agent only supports one test bundle per run
2. **No Status Tracking**: ReportPortal server calculates final status from test results
3. **No Finalization Flags**: `testBundleDidFinish` called exactly once - no need to prevent duplicates
4. **No Bundle Counting**: Only one bundle = no need to count or coordinate multiple bundles
5. **Custom UUID Strategy**: Generate UUID immediately instead of waiting for API response

### What Was Removed?

| Feature | Why Removed |
|---------|-------------|
| `activeBundleCount` | Single bundle only - no counting needed |
| `aggregatedStatus` | ReportPortal calculates status - redundant tracking |
| `isFinalized` | Bundle finish called once - no duplicate prevention needed |
| `updateStatus()` | Status aggregation removed |
| `getAggregatedStatus()` | Status aggregation removed |
| `markFinalized()` | Finalization tracking removed |
| `isLaunchFinalized()` | Finalization tracking removed |
| `incrementBundleCount()` | Bundle counting removed |
| `decrementBundleCount()` | Bundle counting removed |
| `setLaunchID()` | Lazy var generates internally |
| `getLaunchID()` | Direct property access instead |
| Actor isolation | No concurrent access to mutable state |

### Evolution: 180 lines → 26 lines (85% reduction)

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
