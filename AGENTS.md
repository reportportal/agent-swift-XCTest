# Repository Guidelines

## Project Structure & Module Organization
- `Sources/` — Swift library code (`ReportPortalAgent`): `Entities/`, `EndPoints/`, `Utilities/`, core types like `ReportingService` and `RPListener`.
- `Example/` — sample iOS app and `Example.xctestplan`.
- `ExampleUnitTests/`, `ExampleUITests/` — XCTest and XCUITest bundles.
- `ReportPortalAgent.xcodeproj`, `Package.swift`, `ReportPortal.podspec` — Xcode, SPM, and CocoaPods config.
- `.github/workflows/` — CI for CocoaPods lint and build.

## Build, Test, and Development Commands
- Build (SPM library): `swift build`
- Build (Xcode): `xcodebuild build -project ReportPortalAgent.xcodeproj -scheme Example -destination 'platform=iOS Simulator,name=iPhone 15'`
- Test (sequential only): `xcodebuild test -project ReportPortalAgent.xcodeproj -scheme Example -testPlan Example -destination 'platform=iOS Simulator,name=iPhone 15'`
- Podspec lint: `pod lib lint --allow-warnings`

## Coding Style & Naming Conventions
- Swift 4.2+ (tools 5.1). Use 2‑space indentation; avoid trailing whitespace.
- Types `UpperCamelCase`; methods/vars `lowerCamelCase`; filenames match the primary type.
- Keep modules cohesive: networking in `Utilities/HTTPClient.swift`, models in `Entities/`, endpoints in `EndPoints/`.
- No SwiftLint config is checked in; follow Swift API Design Guidelines and prefer small, focused types.

## Testing Guidelines
- Frameworks: `XCTest` and `XCUITest`. Name tests `test...` and keep them deterministic.
- Unit tests in `ExampleUnitTests/`; UI tests in `ExampleUITests/`.
- ReportPortal integration: set keys in the test target `Info.plist` and principal class `ReportPortalAgent.RPListener` (SPM) or `ReportPortal.RPListener` (CocoaPods).
- Optional: override plan name `TEST_PLAN_NAME="Nightly" xcodebuild test ...`. Parallel execution is not supported.

## Commit & Pull Request Guidelines
- Commits: short, imperative subjects; common prefixes seen: `[add]`, `[fix]`, `[update]` (e.g., `[fix] reporting timeout in finishLaunch`).
- Pull Requests: clear description, linked issues, CI green, update README/CHANGELOG if behavior changes; include logs/screenshots for UI changes where helpful.

## Security & Configuration Tips
- In `DEBUG`, `HTTPClient` relaxes SSL for proxy testing; never rely on this in production.
- Do not commit tokens; provide ReportPortal URL/token/launch in test target `Info.plist`.
