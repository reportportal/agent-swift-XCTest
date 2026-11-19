# Changelog

## [Unreleased]

### Added
- **One launch per device-farm run:** `ReportPortalLaunchUUID` in the test bundle's `Info.plist`.
  Real devices never see environment variables, but every shard and every farm retry gets the
  compiled-in plist, so they all report into one launch and no post-run merge is needed. The
  agent then leaves finishing that launch to one CI step after all shards
  (`ReportPortalSkipFinish` defaults to on), by @rusel95.
- **Retries in one row:** `ReportPortalCollapseRetries` / `RP_COLLAPSE_RETRIES` (opt-in). A
  retried test is one row with the status of its last attempt and the earlier attempts nested
  under it, also when the retry ran on another device, by @rusel95.
- Tests and suites carry `codeRef` and `testCaseId`, so history follows a test across launches
  (it starts over once after the upgrade). Tests in a shared launch carry `device` and `os`,
  by @rusel95.

### Fixed
- Failed runs showed as passed: the launch and suites were finished with an explicit `PASSED`.
  They now finish without a status, so ReportPortal derives it from the tests, by @rusel95.
- Skipped tests were reported as `PASSED`; they are `SKIPPED` now. ReportPortal then shows a
  launch with skipped tests as failed, as with other agents, by @rusel95.
- Requests could reach ReportPortal out of order: a suite finished before its last test, a test
  before its start returned. Each test's requests now go out in order and a suite finishes after
  its tests, by @rusel95.
- Tests of a nested or `@objc(Name)` test class were reported late, interrupted or not at all,
  by @rusel95.
- Every test process waited 20 s at the end and logged a timeout; it now waits only for the
  requests still in flight, by @rusel95.
- A device whose clock lags the shared launch's creator lost its results; the agent never stamps
  earlier than the start time ReportPortal stored, by @rusel95.
- Reading a launch never worked (a GET carried a JSON body, epoch timestamps failed to decode).
  The `device` attribute read `arm64` on Apple-silicon simulators. A failure screenshot is
  taken at the failure, not when its upload gets its turn, by @rusel95.
- **Random loss of all launch attributes (the real "N of 6 didn't merge" cause).** The
  start-launch and start-item bodies sent a legacy `"tags"` field alongside `"attributes"`.
  Server-side, ReportPortal's `StartRQ` declares `@JsonAlias({"attributes","tags"})` — both
  names bind to the SAME property and Jackson keeps whichever appears last in the JSON.
  Swift dictionaries serialize in per-process random key order, so each test process was a
  coin flip: when `"tags"` serialized after `"attributes"`, the keyless tag strings replaced
  every keyed attribute (`merge_group`, `device`, `os`, …), making the launch invisible to
  the post-run merge. The legacy `"tags"` field is no longer sent (tags already reach RP as
  keyed `tag` attributes), by @rusel95.

### Removed
- The orphan-launch attribute back-fill on HTTP 409: ReportPortal's v2 API never answers a
  launch start with 409, so it never ran, by @rusel95.

## [4.1.0] - 2026-06-09

### Fixed
- Launch gate eliminates the actor priority inversion that caused some parallel
  shards to lose all attributes ("merged 4 of 6"). Suites/tests now await a single
  launch-creation Task and skip reporting when launch creation ultimately fails,
  by @rusel95.
- Launch finalization treats only HTTP 409 (already finished) as non-fatal; every
  other HTTP status and non-HTTP error now propagates, by @rusel95.
- Orphan-launch attribute back-fill: when `startLaunch` returns 409 (a launch with the
  same UUID already exists — e.g. an "orphan" ReportPortal auto-created from the first
  test-item POST on a real-device farm), the agent now resolves that launch's numeric id
  and PUTs the full attribute set onto it, so `merge_group` is present and the post-run
  merge can find it. Previously such launches stayed attribute-less and were skipped by
  the merge ("3 of 6"), by @rusel95.

### Added
- SauceLabs real-device merge support: `RP_MERGE_GROUP` / `ReportPortalMergeGroup`
  (`merge_group` attribute), `RP_SKIP_FINISH` / `ReportPortalSkipFinish` (defer
  finalization to a post-run merge script), and `RP_CI_RUN_ID` / `GITHUB_RUN_ID`
  (`ci_run_id` attribute to disambiguate concurrent CI runs), by @rusel95.
- Launch creation retries up to 3 times with exponential backoff on transient
  errors, by @rusel95.
- `docs/SAUCELABS_SETUP.md` — self-contained guide for the SauceLabs real-device
  merge: setup steps, the vendorable merge script, a GitHub Actions workflow, and a
  copy-paste prompt for wiring it into a consuming repo with an AI agent, by @rusel95.

### Changed
- `LaunchManager` actor replaced by a caseless `LaunchUUID` enum that resolves the
  per-process launch UUID once (`RP_LAUNCH_UUID` env var or auto-generated), by @rusel95.
- CocoaPod deployment targets lowered to the library's actual floor — iOS 15 /
  macOS 12 / tvOS 15 — to match `Package.swift`. The podspec previously
  over-declared iOS 18.6 / macOS 14.0 / tvOS 18.2, by @rusel95.

### Removed
- Unused `GetCurrentLaunchEndPoint` (dead after the V2 API migration), by @rusel95.

## [4.0.1] - 2025-12-12

## [4.0.0] - 2025-11-21

### Changed
- **BREAKING**: LaunchManager simplified from Actor to simple singleton class, by @rusel95
  - Changed from ~180 lines to 26 lines (85% reduction)
  - Removed bundle counting (activeBundleCount, increment/decrement methods)
  - Removed status aggregation (updateStatus, getAggregatedStatus methods)
  - Removed finalization tracking (isFinalized, markFinalized methods)
  - Launch ID now lazy var with custom UUID generation (no API waiting)
  - Direct property access: `LaunchManager.shared.launchID` instead of async methods
- Custom UUID Strategy: Generate launch UUID client-side instead of waiting for API response, by @rusel95
  - Eliminates race conditions, timeout logic, and complex synchronization
  - UUID immediately available for all test operations
  - ReportPortal launch creation happens asynchronously in background
- Removed redundant status tracking - ReportPortal server calculates final status, by @rusel95
- Single bundle execution model (no multi-bundle coordination), by @rusel95

## [3.1.3] - 2025-09-11
### Added
- Enhanced error messages with metadata (device info, timestamps, test context), by @rusel95
### Fixed
- Missing Line Numbers in Error Messages, by @rusel95
- Dynamic Suite Naming Not Working, by @rusel95

## [3.1.2] - 2025-08-07

## [3.1.1] - 2025-07-18
### Fixed
- Attachments to log entries, by @rusel95

## [3.1.0] - 2025-06-25
### Fixed
- [Issue #10](https://github.com/reportportal/agent-swift-XCTest/issues/10): Integrate reportportal with XCUItests, by @rusel95
- [Issue #11](https://github.com/reportportal/agent-swift-XCTest/issues/11): testSuiteIdNotFound Issue, by @rusel95

## [3.0.4] - 2025-04-11
### Fixed
- [Issue #13](https://github.com/reportportal/agent-swift-XCTest/issues/13): TypeMismatch for startTime endTime lastModified, by @rusel95

## [3.0.3] - 2024-11-12
### Fixed
- [Issue #8](https://github.com/reportportal/agent-swift-XCTest/issues/8): Failed tests don't show exception logs in ReportPortal, by @YauheniPo

## [3.0.2] - 2024-04-30

## [3.0.2] - 2024-04-30

### Added
- Validation and Release flows

### Updated
- Update podspec manifest

## [2.4.0]
### Added
- Client version updated
