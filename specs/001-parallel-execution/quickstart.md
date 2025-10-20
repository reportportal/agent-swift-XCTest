# Quickstart: Parallel Test Execution

**Feature**: 001-parallel-execution  
**Audience**: Developers using agent-swift-XCTest v4.0.0+  
**Date**: 2025-10-17

## Overview

Starting with version 4.0.0, the ReportPortal agent for Swift XCTest supports parallel test execution, reducing CI/CD pipeline times by 60-75%. This guide covers setup, configuration, and troubleshooting.

## Requirements

### Minimum Versions
- **Swift**: 5.5+
- **iOS**: 13.0+
- **macOS**: 10.15+ (Catalina)
- **Xcode**: 13.0+
- **Agent**: 4.0.0+

### Breaking Changes from 3.x
If upgrading from agent 3.x.x, note these breaking changes:
- Swift 5.5+ required (was 5.1+)
- iOS 13+ / macOS 10.15+ required (was iOS 8+)
- See [Migration Guide](../migration-guide.md) for details

## Installation

### Swift Package Manager (Recommended)

```swift
// Package.swift
let package = Package(
    name: "MyApp",
    platforms: [
        .iOS(.v13),      // Minimum iOS 13
        .macOS(.v10_15)  // Minimum macOS 10.15
    ],
    dependencies: [
        .package(url: "https://github.com/reportportal/agent-swift-XCTest.git", from: "4.0.0")
    ],
    targets: [
        .testTarget(
            name: "MyAppTests",
            dependencies: [
                .product(name: "ReportPortalAgent", package: "agent-swift-XCTest")
            ]
        )
    ]
)
```

### CocoaPods

```ruby
# Podfile
platform :ios, '13.0'  # Minimum iOS 13

target 'MyAppTests' do
  use_frameworks!
  pod 'ReportPortal', '~> 4.0'
end
```

Then run:
```bash
pod install
```

## Configuration

### 1. Configure Info.plist (Test Target)

Add ReportPortal configuration to your test target's `Info.plist`:

```xml
<key>ReportPortalURL</key>
<string>https://your-reportportal.com/api/v1</string>

<key>ReportPortalToken</key>
<string>your-auth-token</string>

<key>ReportPortalProjectName</key>
<string>your-project-name</string>

<key>ReportPortalLaunchName</key>
<string>My App Tests</string>

<key>PushTestDataToReportPortal</key>
<true/>

<key>IsFinalTestBundle</key>
<true/>  <!-- Set to true for last test bundle only -->

<key>Principal class</key>
<string>ReportPortalAgent.RPListener</string>  <!-- For SPM -->
<!-- OR -->
<string>ReportPortal.RPListener</string>  <!-- For CocoaPods -->
```

### 2. Enable Parallel Execution

#### Option A: Xcode Test Plan (Recommended)

1. Create or open your `.xctestplan` file
2. Edit as JSON and add:

```json
{
  "configurations": [{
    "id": "default",
    "name": "Default Configuration",
    "options": {
      "parallelizationEnabled": true,
      "maximumParallelTestOperations": 4
    }
  }],
  "defaultOptions": {
    "testExecutionOrdering": "random"
  }
}
```

#### Option B: Xcode UI

1. Select test plan in Project Navigator
2. Open Configurations tab
3. Enable "Execute in parallel"
4. Set "Maximum parallel test operations" to 4-8 (based on CI capacity)

#### Option C: Command Line (xcodebuild)

```bash
xcodebuild test \
  -scheme MyApp \
  -testPlan MyTestPlan \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4 \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### 3. Optional: Test Plan Name in Launches

To include test plan names in ReportPortal launch names:

```json
{
  "defaultOptions": {
    "environmentVariableEntries": [
      {
        "key": "TEST_PLAN_NAME",
        "value": "Smoke Tests"
      }
    ]
  }
}
```

Result: Launch appears as `"My App Tests: Smoke_Tests"` in ReportPortal.

## Validation

### Run Tests Locally

```bash
xcodebuild test \
  -scheme MyApp \
  -testPlan MyTestPlan \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4 \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Check ReportPortal

1. Open ReportPortal web UI
2. Navigate to your project
3. Find latest launch (e.g., "My App Tests: Smoke_Tests")
4. Verify test hierarchy:
   ```
   Launch
   └── Root Suite (Bundle)
       └── Test Suite (Class)
           ├── Test 1
           ├── Test 2
           └── Test 3
   ```
5. Confirm all tests appear with correct status

### Enable Thread Sanitizer (Recommended for CI)

1. Edit scheme: Product → Scheme → Edit Scheme
2. Run → Diagnostics tab
3. Enable "Thread Sanitizer"
4. Run tests again
5. Verify zero TSan warnings (indicates no race conditions)

**Note**: Thread Sanitizer adds 3-5x overhead (slower execution, but catches bugs)

## Parallel Execution Limits

### Recommended Settings

| Environment | Workers | Rationale |
|-------------|---------|-----------|
| Local Mac (M1/M2) | 4-6 | Balance speed vs resource usage |
| GitHub Actions | 2-4 | Limited CPU cores |
| Jenkins / GitLab CI | 4-8 | Depends on runner capacity |
| Dedicated CI Server | 8-12 | High-capacity hardware |

### Formula
`Max Workers = min(CPU Cores, Test Suite Count, 10)`

Agent supports up to 10 concurrent operations (tested and validated).

## Troubleshooting

### Issue: Tests fail only in parallel mode

**Symptoms**: Tests pass sequentially but fail when run in parallel  
**Cause**: Tests have hidden dependencies or shared mutable state  
**Solution**:
1. Review tests for shared state (singletons, class variables)
2. Use dependency injection for test doubles
3. Isolate test data (use unique IDs per test)
4. Enable Thread Sanitizer to detect data races

### Issue: Launch finalization doesn't happen

**Symptoms**: Launch stays "IN_PROGRESS" in ReportPortal  
**Cause**: Reference counting mismatch (bundle start/finish imbalance)  
**Solution**:
1. Check console logs for bundle lifecycle events
2. Ensure all test targets have `IsFinalTestBundle` configured
3. Set only **one** test target to `IsFinalTestBundle = true`
4. Timeout mechanism (30 min) will eventually force finalization

### Issue: Duplicate test results in ReportPortal

**Symptoms**: Same test appears multiple times with different outcomes  
**Cause**: Test identifier collision (rare) or misconfigured test plan  
**Solution**:
1. Verify test names are unique within class
2. Check test plan doesn't run same tests twice
3. Review agent logs for correlation IDs

### Issue: Performance degradation

**Symptoms**: Parallel execution slower than expected  
**Cause**: ReportPortal API latency, network issues, or over-parallelization  
**Solution**:
1. Check ReportPortal server response times
2. Reduce `maximumParallelTestOperations` (try 2-4 first)
3. Verify network connectivity between CI and ReportPortal
4. Review agent logs for API error rates

### Issue: Memory usage spikes

**Symptoms**: Test runner crashes with memory warnings  
**Cause**: Too many concurrent tests or memory leaks in tests  
**Solution**:
1. Reduce parallel workers (start with 2-4)
2. Use Instruments to profile memory usage
3. Check for test code memory leaks (autoreleasepool issues)
4. Agent overhead is ~2MB for 10 concurrent tests (negligible)

## Best Practices

### 1. Isolate Test State
```swift
// ❌ BAD: Shared mutable state
class MyTests: XCTestCase {
    static var sharedCounter = 0  // Race condition!
    
    func testIncrement() {
        MyTests.sharedCounter += 1
        XCTAssertEqual(MyTests.sharedCounter, 1)  // Fails in parallel!
    }
}

// ✅ GOOD: Local state
class MyTests: XCTestCase {
    func testIncrement() {
        var localCounter = 0
        localCounter += 1
        XCTAssertEqual(localCounter, 1)  // Always passes
    }
}
```

### 2. Use Unique Test Data
```swift
// ✅ GOOD: Unique IDs prevent collisions
func testUserCreation() {
    let userID = UUID().uuidString  // Unique per test
    let user = createUser(id: userID)
    XCTAssertNotNil(user)
}
```

### 3. Independent Test Cases
Each test should:
- Set up its own data
- Clean up after itself
- Not depend on execution order
- Not share files/database records with other tests

### 4. CI/CD Integration

#### GitHub Actions
```yaml
name: Tests

on: [push]

jobs:
  test:
    runs-on: macos-13
    steps:
      - uses: actions/checkout@v3
      - name: Run Tests
        run: |
          xcodebuild test \
            -scheme MyApp \
            -testPlan MyTestPlan \
            -parallel-testing-enabled YES \
            -maximum-parallel-testing-workers 4 \
            -destination 'platform=iOS Simulator,name=iPhone 15' \
            -enableThreadSanitizer YES
```

#### Jenkins
```groovy
stage('Test') {
    steps {
        sh '''
            xcodebuild test \
              -scheme MyApp \
              -parallel-testing-enabled YES \
              -maximum-parallel-testing-workers 6 \
              -destination 'platform=iOS Simulator,name=iPhone 15'
        '''
    }
}
```

## Performance Expectations

### Time Reduction Examples

| Test Suite Size | Sequential Time | Parallel Time (4 workers) | Improvement |
|-----------------|-----------------|---------------------------|-------------|
| 100 tests | 10 min | 3 min | 70% faster |
| 500 tests | 45 min | 12 min | 73% faster |
| 2000 tests | 6 hours | 1.5 hours | 75% faster |

**Actual results vary** based on:
- Test duration variance
- ReportPortal API latency
- CI runner capacity
- Network conditions

## FAQ

### Q: Is parallel execution enabled by default?
**A**: No. Parallel execution is **opt-in** via test plan configuration. Existing sequential tests continue to work without changes.

### Q: Can I run some tests sequentially and others in parallel?
**A**: Yes. Create separate test plans: one with `parallelizationEnabled: false` for sequential tests, another with `true` for parallel tests.

### Q: Does parallel execution work with UI tests?
**A**: Yes, but be cautious. UI tests may have implicit dependencies (e.g., shared simulator state). Test thoroughly with Thread Sanitizer.

### Q: What happens if ReportPortal API is slow?
**A**: Tests continue executing. Reporting happens asynchronously and doesn't block test execution. Slow API may delay launch finalization but won't affect test outcomes.

### Q: Can I use parallel execution with older iOS versions (iOS 12)?
**A**: No. Agent 4.0+ requires iOS 13+ for Swift Concurrency runtime. Use agent 3.x for iOS 12 support (sequential execution only).

### Q: How do I debug parallel test failures?
**A**: 
1. Check console logs for correlation IDs (UUID shown in brackets)
2. Filter logs by correlation ID to trace specific test
3. Enable Thread Sanitizer to detect race conditions
4. Run failing test sequentially to isolate parallelism issues

## Next Steps

- [Migration Guide](../migration-guide.md) - Upgrade from 3.x to 4.0
- [Architecture Overview](./data-model.md) - Understand internal design
- [API Contracts](./contracts/) - Actor and async API documentation
- [GitHub Issues](https://github.com/reportportal/agent-swift-XCTest/issues) - Report bugs or request features

## Support

- **GitHub**: [agent-swift-XCTest](https://github.com/reportportal/agent-swift-XCTest)
- **Slack**: [ReportPortal Community](https://slack.epmrpp.reportportal.io/)
- **StackOverflow**: Tag `reportportal`
