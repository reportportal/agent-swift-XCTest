# XCTest Agent for ReportPortal


[![CocoaPods](https://img.shields.io/cocoapods/v/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![Platform](https://img.shields.io/cocoapods/p/ReportPortal.svg?style=flat)](http://cocoapods.org/pods/ReportPortal)
[![Validate](https://github.com/reportportal/agent-swift-XCTest/actions/workflows/validate.yml/badge.svg)](https://github.com/reportportal/agent-swift-XCTest/actions/workflows/validate.yml)
[![Join Slack chat!](https://img.shields.io/badge/slack-join-brightgreen.svg)](https://slack.epmrpp.reportportal.io/)
[![stackoverflow](https://img.shields.io/badge/reportportal-stackoverflow-orange.svg?style=flat)](http://stackoverflow.com/questions/tagged/reportportal)
[![Build with Love](https://img.shields.io/badge/build%20with-❤%EF%B8%8F%E2%80%8D-lightgrey.svg)](http://reportportal.io?style=flat)
[![License](https://img.shields.io/badge/License-Apache%202.0-blue.svg)](https://opensource.org/licenses/Apache-2.0)

## Installation

ReportPortalAgent is available through [CocoaPods](http://cocoapods.org). To install
it, simply add the following line to your Podfile:

```ruby
pod 'ReportPortal'
```
and install it:
```bash
cd <project>
pod install
```

Also available through SPM by name "agent-swift-xctest" or URL of current repo

## Report Portal properties

The properties for Report Portal configuration should be set in the `Info.plist` file of your Test Target. If you Test Target does't have an `Info.plist`, follow these steps to add:

1. In your Test Target Folder, create a Property List named `Info.plist`.
2. In Test Target Settings, configure 'Info.plist File' with the path `TestTargetFolderName/Info.plist`.

Now, you can specify the Report Portal properties:

* ReportPortalURL - Base URL of your ReportPortal instance (example: https://report-portal.company.com). The agent automatically appends `/api/v2/{project}` to construct the full API URL.
* ReportPortalToken - token for authentication which you can get from RP account settings.
* ReportPortalLaunchName - name of launch.
* Principal class - use `ReportPortalAgent.RPListener` from ReportPortalAgent lib for SPM or `ReportPortal.RPListener` for CocoaPods. You can also specify your own Observer which should conform to [XCTestObservation](https://developer.apple.com/documentation/xctest/xctestobservation) protocol.
* PushTestDataToReportPortal - can be used to switch off/on reporting
* ReportPortalProjectName - project name from Report Portal
* ReportPortalTags(optional) - can be used to specify tags, separated by comma.

Example:
![Alt text](./Example.png)

## Optional: Test Plan Name visibility

To include test plan names in ReportPortal, add the `TEST_PLAN_NAME` environment variable to your `.xctestplan` file manually:

```json
{
  "defaultOptions": {
    "environmentVariableEntries": [
      {
        "key": "TEST_PLAN_NAME",
        "value": "Example Test Plan"
      }
    ]
  }
}
```
Or in XCode:
![Alt text](./TEST_PLAN_NAME.png)

**Result:** Launch names will appear as `YourLaunchName: Example_Test_Plan` in ReportPortal.

**Note:** Spaces in test plan names are automatically replaced with underscores for better compatibility.

**CI Override:** CI can override this value: `TEST_PLAN_NAME="Nightly Tests" xcodebuild test ...`

## Parallel Test Execution (v4.0+)

Starting with v4.0, the agent fully supports **parallel test execution**, allowing you to dramatically reduce CI/CD pipeline times. Tests can be executed across multiple simulator instances simultaneously while maintaining proper test hierarchy and reporting in ReportPortal.

### Requirements

- **iOS 15.0+** / **macOS 14.0+** (required for Swift Concurrency)
- **Swift 5.5+**
- **Xcode 13+**

### Configuration

Parallel execution is controlled via `xcodebuild` command-line arguments. No `.xctestplan` modifications are required.

#### Run Tests with Parallel Execution

**Option A: Single Device Type (Multiple Clones)**

This approach clones the same simulator multiple times. Best for consistent test environments:

```bash
xcodebuild test \
  -scheme YourScheme \
  -testPlan YourTestPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

This will create 4 simulator clones: `iPhone 16 - Clone 1`, `iPhone 16 - Clone 2`, etc.

**Option B: Multiple Device Types (Explicit Devices)**

Run tests across different device models simultaneously. Great for device coverage:

```bash
xcodebuild test \
  -scheme YourScheme \
  -testPlan YourTestPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -destination 'platform=iOS Simulator,name=iPhone 15 Pro' \
  -destination 'platform=iOS Simulator,name=iPhone 15' \
  -destination 'platform=iOS Simulator,name=iPhone 14' \
  -parallel-testing-enabled YES
```

**Option C: GitHub Actions Example**

```yaml
- name: Run Tests in Parallel
  run: |
    xcodebuild test \
      -scheme MyApp \
      -testPlan MyTestPlan \
      -parallel-testing-enabled YES \
      -maximum-parallel-testing-workers 2 \
      -resultBundlePath TestResults.xcresult
```

**Option D: Bitrise Example**

```yaml
- xcode-test@4:
    inputs:
      - scheme: MyApp
      - test_plan: MyTestPlan
      - simulator_device: iPhone 16
```

### CI/CD: Single Shared Launch (Recommended)

By default, parallel execution creates **separate launches per worker** (e.g., 4 workers = 4 launches in ReportPortal). In local development, this is acceptable (you can manually merge launches in ReportPortal UI).

For CI/CD pipelines, you can configure **all workers to report to a single shared launch** using the `RP_LAUNCH_UUID` environment variable:

```bash
# Generate UUID and run tests with shared launch
export RP_LAUNCH_UUID=$(uuidgen)

xcodebuild test \
  -scheme YourScheme \
  -testPlan YourTestPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

**How it works:**
1. `export RP_LAUNCH_UUID=$(uuidgen)` sets a shared UUID **before** running tests
2. All parallel workers read the **same UUID** from environment
3. First worker creates the launch in ReportPortal
4. Other workers join the existing launch (409 Conflict handled automatically)
5. Result: **Single launch** in ReportPortal containing all test results

**Why NOT use build phase scripts for UUID generation:**

Build phase scripts only run when **source files change** (Xcode incremental build). If you re-run tests without code changes, the UUID stays stale and workers join the **previous test run's launch**, causing data corruption.

```bash
# ❌ DON'T DO THIS - Build phases don't run on every test execution!
# Build Phase → Run Script:
UUID=$(uuidgen)
/usr/libexec/PlistBuddy -c "Set :RP_LAUNCH_UUID $UUID" Info.plist
```

**Timeline showing the problem:**
```
10:00 - Run tests → Build runs → UUID-AAA generated → Launch created ✅
10:05 - Re-run tests → NO BUILD → Still UUID-AAA → Joins old launch ❌
10:10 - Re-run tests → NO BUILD → Still UUID-AAA → ERROR: Launch already finalized ❌
10:15 - Change code → Build runs → UUID-BBB generated → New launch ✅
```

**Solution:** Use environment variables set by CI/CD pipeline (always fresh, always unique per test run).

### Local Development: Multiple Launches

In local development (Xcode IDE), each parallel worker creates a **separate launch**:

```
ReportPortal Dashboard:
├── MyApp Tests - iPhone 16 Clone 1 (Worker 1)
├── MyApp Tests - iPhone 16 Clone 2 (Worker 2)
├── MyApp Tests - iPhone 16 Clone 3 (Worker 3)
└── MyApp Tests - iPhone 16 Clone 4 (Worker 4)
```

**To run with a single shared launch locally (via script):**

```bash
#!/bin/bash
# run_tests_shared_launch.sh

# Generate UUID once for this test run
export RP_LAUNCH_UUID=$(uuidgen)

echo "Running tests with shared launch UUID: $RP_LAUNCH_UUID"

xcodebuild test \
  -scheme MyApp \
  -testPlan MyTestPlan \
  -destination 'platform=iOS Simulator,name=iPhone 16' \
  -parallel-testing-enabled YES \
  -maximum-parallel-testing-workers 4
```

**To merge launches manually (when running from Xcode IDE):**
1. Go to ReportPortal → Launches
2. Select the 4 launches
3. Click "Merge" → Enter merged launch name
4. All test results combined into single launch

**Why environment variables from Xcode don't work:**

Environment variables set in Xcode Scheme → Pre-Actions **don't propagate to parallel workers** (they run in isolated processes). The script approach above works because `export` sets the variable in the shell session before launching xcodebuild.

### Worker Count Recommendations

Choose worker count based on your CI/CD environment:

| Environment | Recommended Workers | Reasoning |
|-------------|---------------------|-----------|
| **Local Development** (8+ cores) | 4 | Balanced performance without overloading machine |
| **Local Development** (4-6 cores) | 2-3 | Prevents resource contention |
| **GitHub Actions** | 2 | Limited CI resources (7GB RAM, 2 cores) |
| **Bitrise** | 3-4 | Better resource availability |
| **Jenkins** (self-hosted) | CPU count / 2 | Scale with available hardware |
| **GitLab CI** | 2-3 | Standard runner specs |

### Verifying Parallel Execution

When tests run in parallel, you should see output like:

```
Testing started on 'iPhone 16 - Clone 1'
Testing started on 'iPhone 16 - Clone 2'
Testing started on 'iPhone 16 - Clone 3'
Testing started on 'iPhone 16 - Clone 4'
```

In ReportPortal, all test results will appear under a **single launch** with proper test hierarchy maintained.

### Performance Impact

**Example: ExampleUITests**

| Configuration | Execution Time | Improvement |
|--------------|----------------|-------------|
| Sequential (v3.x) | ~40 minutes | Baseline |
| Sequential (v4.x) | ~30 minutes | **25% faster** |
| Parallel - 2 workers | ~15 minutes | **160% faster** |
| Parallel - 3 workers | ~10 minutes | **300% faster** |

---

## 📚 Documentation

This README serves as the central hub for all documentation. Below are links to detailed guides organized by audience.

### For End Users

| Document | Description |
|----------|-------------|
| **[CHANGELOG.md](./CHANGELOG.md)** | Release history, version notes, and change log |
| **[README.md](./README.md)** | Installation, configuration, and parallel execution setup |

### For Developers & Contributors

| Document | Description |
|----------|-------------|
| **[ARCHITECTURE.md](./ARCHITECTURE.md)** | System architecture, concurrency model, V2 API structure, sequence diagrams, and design rationale |
| **[.github/copilot-instructions.md](./.github/copilot-instructions.md)** | Development guidelines, Swift Concurrency best practices, recent changes, and coding standards |
| **[docs/NEXT_STEPS_LAUNCH_SYNCHRONIZATION.md](./docs/NEXT_STEPS_LAUNCH_SYNCHRONIZATION.md)** | Future enhancements for launch coordination (branch 002 analysis) |

### Quick Links

- **Getting Started**: See [Installation](#installation) and [Report Portal properties](#report-portal-properties) above
- **Parallel Execution Setup**: See [Parallel Test Execution (v4.0+)](#parallel-test-execution-v40) section
- **CI/CD Integration**: See examples in [Parallel Test Execution](#parallel-test-execution-v40) section
- **Architecture Overview**: Start with [ARCHITECTURE.md](./ARCHITECTURE.md) for diagrams and design decisions
- **Recent Changes**: Check [.github/copilot-instructions.md](./.github/copilot-instructions.md) for latest updates

---

## Authors
[@rusel95](https://github.com/rusel95), <ruslanpopesku95@gmail.com>

ReportPortal Team, <support@reportportal.io>

@DarthRumata, <stas.kirichok@windmill.ch> ([Windmill Smart Solutions](https://github.com/Windmill-Smart-Solutions))

@SergeVKom, <sergvkom@gmail.com> (original library)

## License

Licensed under the [Apache 2.0](https://www.apache.org/licenses/LICENSE-2.0) license (see the LICENSE file).
