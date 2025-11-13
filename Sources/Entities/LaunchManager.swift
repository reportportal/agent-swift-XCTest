//
//  LaunchManager.swift
//  ReportPortalAgent
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation

/// Launch coordination with V2 API synchronization
/// Ensures launch exists before any suite/test reporting starts
///
/// ## Launch UUID Strategy:
/// 1. **CI/CD Mode**: Use `RP_LAUNCH_UUID` environment variable (all workers share same launch)
/// 2. **Local Mode**: Generate unique UUID per worker (separate launches, manual merge needed)
///
/// ## V2 API Launch Creation:
/// - First worker creates launch via V2 API with UUID
/// - Subsequent workers get 409 Conflict (expected, means launch exists)
/// - All workers wait for launch to be confirmed before reporting suites/tests
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
actor LaunchManager {
    /// Shared singleton instance
    static let shared = LaunchManager()

    /// Private initializer ensures singleton pattern
    private init() {}

    /// Launch creation task for synchronization
    /// Multiple workers calling `ensureLaunchStarted()` will share this task
    private var launchCreationTask: Task<Void, Never>?
    
    /// Flag indicating launch is ready for suite/test reporting
    private var isLaunchReady = false

    /// Cached launch UUID (initialized once on first access)
    /// Uses Obj-C dispatch_once guarantee via lazy static for thread safety
    private static let generatedUUID: String = {
        let uuid = UUID().uuidString
        Logger.shared.info("📦 [Local Mode] Generated unique launch UUID: \(uuid)")
        Logger.shared.info("ℹ️  [Local Mode] Each parallel worker creates separate launch (manual merge needed)")
        return uuid
    }()

    /// ReportPortal launch ID (custom UUID, resolved synchronously)
    ///
    /// ## UUID Resolution Priority:
    /// 1. `RP_LAUNCH_UUID` environment variable (CI/CD shared launch)
    /// 2. Client-generated UUID (local development, separate launches per worker)
    ///
    /// ## Parallel Execution Behavior:
    /// - **CI/CD**: All workers read same `RP_LAUNCH_UUID` → Single shared launch
    /// - **Local**: Each worker generates own UUID → Separate launches (4 workers = 4 launches)
    ///
    /// ## Thread Safety:
    /// Reads environment variables (immutable after process start) or uses static lazy UUID.
    /// Marked nonisolated for synchronous access from non-actor contexts.
    nonisolated var launchID: String {
        // Priority 1: Check for CI/CD provided UUID
        if let ciUUID = ProcessInfo.processInfo.environment["RP_LAUNCH_UUID"] {
            Logger.shared.info("📦 [CI Mode] Using shared launch UUID from environment: \(ciUUID)")
            return ciUUID
        }
        
        // Priority 2: Use pre-generated static UUID (initialized once per process)
        return Self.generatedUUID
    }
    
    /// Ensure launch has been started via V2 API before allowing suite/test creation
    /// - Parameter startLaunch: Async closure that calls ReportPortal V2 API
    /// 
    /// ## Synchronization Behavior:
    /// - First caller creates launch via V2 API
    /// - Subsequent callers wait for launch to be ready
    /// - 409 Conflict handled gracefully (launch already exists = success)
    ///
    /// ## Usage:
    /// ```swift
    /// await LaunchManager.shared.ensureLaunchStarted {
    ///     try await reportingService.startLaunch(...)
    /// }
    /// ```
    func ensureLaunchStarted(_ startLaunch: @escaping () async throws -> Void) async {
        // Fast path: launch already ready
        if isLaunchReady {
            Logger.shared.info("✅ Launch already started, proceeding with reporting")
            return
        }
        
        // Check if launch creation is in progress
        if let existingTask = launchCreationTask {
            Logger.shared.info("⏳ Launch creation in progress, waiting for completion...")
            await existingTask.value
            return
        }
        
        // Create launch creation task (first worker to reach here)
        let task = Task {
            Logger.shared.info("🚀 Starting launch creation via V2 API...")
            
            do {
                try await startLaunch()
                markLaunchReady()
                Logger.shared.info("✅ Launch successfully started and ready for reporting")
            } catch let error as HTTPClientError {
                // Handle 409 Conflict - expected in CI/CD when multiple workers use same UUID
                if case .httpError(let statusCode, _) = error, statusCode == 409 {
                    markLaunchReady()
                    Logger.shared.info("✅ Launch already exists (409 Conflict) - this is EXPECTED in CI/CD mode")
                    Logger.shared.info("✅ Launch ready for reporting")
                } else {
                    Logger.shared.error("❌ Launch creation failed: \(error.localizedDescription)")
                    Logger.shared.error("⚠️  Reporting will be disabled for this worker")
                    // Don't mark as ready - this worker won't report
                }
            } catch {
                Logger.shared.error("❌ Launch creation failed: \(error.localizedDescription)")
                Logger.shared.error("⚠️  Reporting will be disabled for this worker")
                // Don't mark as ready - this worker won't report
            }
        }
        
        launchCreationTask = task
        await task.value
    }
    
    /// Mark launch as ready for reporting (private helper)
    private func markLaunchReady() {
        isLaunchReady = true
    }
    
    /// Check if launch is ready for suite/test reporting
    /// - Returns: True if launch has been successfully started
    func isReady() -> Bool {
        return isLaunchReady
    }
}

