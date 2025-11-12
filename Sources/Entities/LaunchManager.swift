//
//  LaunchManager.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation

/// Minimal launch state management for single bundle execution.
/// Only stores the launch UUID - no complex state tracking needed.
///
/// ## Launch UUID Strategy:
/// 1. **CI/CD Mode**: Use `RP_LAUNCH_UUID` environment variable (all workers share same launch)
/// 2. **Local Mode**: Generate unique UUID per worker (separate launches, manual merge needed)
///
/// ### CI/CD Setup:
/// ```bash
/// # In CI/CD pipeline (GitHub Actions, Jenkins, etc.)
/// export RP_LAUNCH_UUID=$(uuidgen)
/// xcodebuild test -scheme MyApp -parallel-testing-enabled YES
/// ```
///
/// ### Why Build Phase UUID Generation Doesn't Work:
/// Build phase scripts only run when source files change (Xcode incremental build).
/// Re-running tests without code changes = stale UUID = joins previous launch = ERROR!
final class LaunchManager {
    /// Shared singleton instance
    static let shared = LaunchManager()

    /// Private initializer ensures singleton pattern
    private init() {}

    /// ReportPortal launch ID (custom UUID, generated lazily on first access)
    ///
    /// ## UUID Resolution Priority:
    /// 1. `RP_LAUNCH_UUID` environment variable (CI/CD shared launch)
    /// 2. Client-generated UUID (local development, separate launches per worker)
    ///
    /// ## Parallel Execution Behavior:
    /// - **CI/CD**: All workers read same `RP_LAUNCH_UUID` → Single shared launch
    /// - **Local**: Each worker generates own UUID → Separate launches (4 workers = 4 launches)
    private(set) lazy var launchID: String = {
        // Priority 1: Check for CI/CD provided UUID
        if let ciUUID = ProcessInfo.processInfo.environment["RP_LAUNCH_UUID"] {
            Logger.shared.info("📦 [CI Mode] Using shared launch UUID from environment: \(ciUUID)")
            return ciUUID
        }
        
        // Priority 2: Generate unique UUID for local development
        let uuid = UUID().uuidString
        Logger.shared.info("📦 [Local Mode] Generated unique launch UUID: \(uuid)")
        Logger.shared.info("ℹ️  [Local Mode] Each parallel worker creates separate launch (manual merge needed)")
        return uuid
    }()
}
