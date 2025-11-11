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
final class LaunchManager {
    /// Shared singleton instance
    static let shared = LaunchManager()

    /// Private initializer ensures singleton pattern
    private init() {}

    /// ReportPortal launch ID (custom UUID, generated lazily on first access)
    private(set) lazy var launchID: String = {
        let uuid = UUID().uuidString
        Logger.shared.info("📦 Launch initialized with UUID: \(uuid)")
        return uuid
    }()
}
