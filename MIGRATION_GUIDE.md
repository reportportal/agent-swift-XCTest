# Migration Guide: v3.x → v4.0

## Overview

ReportPortal Swift Agent v4.0 introduces **parallel test execution support** using Swift Concurrency. This guide will help you migrate from v3.x (sequential execution) to v4.0 (parallel execution).

---

## Quick Start

### For Most Users (No Code Changes Required)

If your app already targets **iOS 15.0+**, migration is simple:

1. **Update dependency**:
   ```ruby
   # Podfile
   pod 'ReportPortal', '~> 4.0'
   ```

2. **Enable parallel execution** in your `.xctestplan`:
   ```json
   {
     "defaultOptions": {
       "parallelizationEnabled": true,
       "maximumParallelTestExecutionWorkers": 4
     }
   }
   ```

3. **That's it!** No code changes needed.

---

## Breaking Changes

### 1. Minimum Deployment Targets

| Platform | v3.x | v4.0 | Change |
|----------|------|------|--------|
| iOS | 12.0+ | **15.0+** | ⚠️ Required |
| macOS | 10.15+ | **12.0+** | ⚠️ Required |
| tvOS | 13.0+ | **15.0+** | ⚠️ Required |
| Swift | 5.1+ | **5.5+** | ⚠️ Required |

**Why?** v4.0 uses `URLSession.data(for:)` and Swift Concurrency APIs available only in iOS 15.0+.

#### Migration Path:

**Option A:** Upgrade your app to iOS 15.0+ (Recommended)
```swift
// Update in Xcode project settings
IPHONEOS_DEPLOYMENT_TARGET = 15.0

// Update in Package.swift
platforms: [.iOS(.v15), .macOS(.v12)]

// Update in Podspec
s.ios.deployment_target = '15.0'
s.osx.deployment_target = '12.0'
```

**Option B:** Stay on v3.x for iOS 12-14 support
```ruby
# Podfile
pod 'ReportPortal', '~> 3.0'
```

---

## Feature Comparison

| Feature | v3.x | v4.0 |
|---------|------|------|
| Sequential Execution | ✅ | ✅ (backward compatible) |
| Parallel Execution | ❌ | ✅ **NEW** |
| Swift Concurrency | ❌ | ✅ **NEW** |
| Thread Safety | Manual locks | Actor isolation |
| Performance | Baseline | 60-75% faster |
| iOS 12-14 Support | ✅ | ❌ |
| iOS 15+ Support | ✅ | ✅ |

---

## Enabling Parallel Execution

### Step 1: Update Test Plan

**In Xcode:**
1. Select your `.xctestplan` file
2. In the inspector, check **"Execute in parallel"**
3. Set **"Maximum Workers"** to **4** (recommended)

**Or manually edit `.xctestplan`:**
```json
{
  "defaultOptions": {
    "parallelizationEnabled": true,
    "maximumParallelTestExecutionWorkers": 4,
    "testExecutionOrdering": "random"  // Optional
  }
}
```

### Step 2: Run Tests

```bash
xcodebuild test \
  -scheme YourScheme \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -testPlan YourTestPlan \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

---

## CI/CD Migration

### GitHub Actions

**Before (v3.x):**
```yaml
- name: Run Tests
  run: |
    xcodebuild test \
      -scheme MyApp \
      -destination 'platform=iOS Simulator,name=iPhone 14'
```

**After (v4.0):**
```yaml
- name: Run Tests
  run: |
    xcodebuild test \
      -scheme MyApp \
      -destination 'platform=iOS Simulator,name=iPhone 16' \
      -testPlan MyTestPlan \
      -parallel-testing-enabled YES \
      -maximum-parallel-testing-workers 2  # Adjust for CI resources
```

### Bitrise

**Before (v3.x):**
```yaml
- xcode-test@4:
    inputs:
      - scheme: MyApp
```

**After (v4.0):**
```yaml
- xcode-test@4:
    inputs:
      - scheme: MyApp
      - xcpretty_test_options: --parallel-testing-enabled --maximum-parallel-testing-workers 3
```

### Jenkins

```groovy
// Before (v3.x)
sh "xcodebuild test -scheme MyApp"

// After (v4.0)
sh """
xcodebuild test \
  -scheme MyApp \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
"""
```

---

## Performance Tuning

### Worker Count Recommendations

| Environment | Recommended Workers | Reasoning |
|-------------|---------------------|-----------|
| Local Mac (8+ cores) | 4 | Balanced performance |
| Local Mac (4-6 cores) | 2-3 | Prevents resource contention |
| GitHub Actions | 2 | Limited CI resources |
| Bitrise | 3-4 | Better resource availability |
| Jenkins | CPU count / 2 | Scales with hardware |

### Test Execution Time Examples

**Example: 1000 UI tests @ 3s each**

| Configuration | Time (Sequential) | Time (Parallel 4 workers) | Improvement |
|---------------|-------------------|---------------------------|-------------|
| v3.x | 50 minutes | N/A | - |
| v4.0 | 50 minutes | 15 minutes | **70%** faster |

---

## Troubleshooting

### Issue: Build Errors with iOS 15 APIs

**Error:**
```
'data(for:delegate:)' is only available in iOS 15.0 or newer
```

**Solution:**
Update deployment target to iOS 15.0+ (see Breaking Changes section above).

---

### Issue: Concurrency Warnings

**Warning:**
```
Concurrency limit reached: 10 active operations (recommended max: 10)
```

**Solution:**
Reduce `maximumParallelTestExecutionWorkers`:
```json
{
  "defaultOptions": {
    "maximumParallelTestExecutionWorkers": 2  // Reduced from 4
  }
}
```

---

### Issue: Flaky Tests in Parallel Mode

**Symptom:** Tests pass sequentially but fail in parallel

**Causes:**
- Shared mutable state between tests
- Race conditions in test code
- Hard-coded delays instead of proper waits

**Solutions:**

1. **Run with Thread Sanitizer** to detect race conditions:
   ```bash
   xcodebuild test -enableThreadSanitizer YES
   ```

2. **Fix shared state:**
   ```swift
   // ❌ Bad: Shared state
   class MyTests: XCTestCase {
       static var sharedData = [String]()  // Race condition!
   }

   // ✅ Good: Instance state
   class MyTests: XCTestCase {
       var testData = [String]()  // Isolated per test
   }
   ```

3. **Use proper waits:**
   ```swift
   // ❌ Bad: Hard-coded delay
   Thread.sleep(forTimeInterval: 2.0)

   // ✅ Good: Conditional wait
   XCTAssertTrue(element.waitForExistence(timeout: 5.0))
   ```

---

### Issue: Tests Slower in Parallel Mode

**Possible Causes:**
- Too many workers causing thread contention
- Memory pressure
- Simulator overhead

**Solutions:**
1. Reduce worker count to 2-3
2. Use physical devices for testing
3. Close unnecessary applications
4. Monitor memory usage during tests

---

## Backward Compatibility

### Running Without Parallel Execution

v4.0 **fully supports sequential execution** (v3.x behavior):

```json
{
  "defaultOptions": {
    "parallelizationEnabled": false  // Same as v3.x
  }
}
```

### API Compatibility

All v3.x public APIs remain unchanged:
- `RPListener` configuration via `Info.plist`
- `ReportPortalURL`, `ReportPortalToken`, etc.
- Test naming rules
- Tag support

---

## Testing Migration

### Step-by-Step Validation

1. **Baseline with v3.x:**
   ```bash
   # Record execution time
   xcodebuild test -scheme MyApp
   ```

2. **Sequential test with v4.0:**
   ```bash
   # Should match v3.x time
   xcodebuild test -scheme MyApp -parallel-testing-enabled NO
   ```

3. **Parallel test with v4.0:**
   ```bash
   # Should be 60-75% faster
   xcodebuild test -scheme MyApp -parallel-testing-enabled YES -maximum-parallel-testing-workers 4
   ```

4. **Thread Sanitizer validation:**
   ```bash
   # Should report 0 data races
   xcodebuild test -scheme MyApp -enableThreadSanitizer YES
   ```

---

## FAQ

### Q: Can I use v4.0 without parallel execution?

**A:** Yes! Set `parallelizationEnabled: false` in your test plan. v4.0 will behave exactly like v3.x.

### Q: Do I need to change my test code?

**A:** No! Tests remain unchanged. Just enable parallel execution in your test plan.

### Q: What if my app targets iOS 14?

**A:** Continue using v3.x until you're ready to upgrade to iOS 15+.

### Q: How do I report issues?

**A:** File an issue at: https://github.com/reportportal/agent-swift-XCTest/issues

### Q: Will parallel execution work with XCUITest?

**A:** Yes! v4.0 fully supports parallel UI test execution.

### Q: Can I mix v3.x and v4.0 in different test targets?

**A:** No. All test targets in a project must use the same version.

---

## Support

- **Documentation:** [README.md](./README.md)
- **Issues:** https://github.com/reportportal/agent-swift-XCTest/issues
- **Slack:** https://slack.epmrpp.reportportal.io/
- **Stack Overflow:** Tag `reportportal`

---

## Version History

- **v4.0.0** (2025-10-22): Parallel execution with Swift Concurrency, iOS 15.0+ required
- **v3.x** (Legacy): Sequential execution, iOS 12.0+ support

---

**Ready to migrate?** Follow the Quick Start guide at the top of this document!
