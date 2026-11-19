//  Created by Ruslan Popesku on 10/22/25.
//  Copyright 2025 EPAM Systems
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import CryptoKit
import Foundation

/// Where the launch UUID came from. A UUID supplied through the `Info.plist` is shared by
/// every shard of the run, so no single process may finalize that launch.
enum LaunchUUIDSource {
    case environment
    case infoPlist
    case generated
}

/// The launch UUID for this process — resolved once, stable across all calls.
///
/// Resolution order:
/// 1. `RP_LAUNCH_UUID` environment variable — parallel simulator clones on one machine.
/// 2. `ReportPortalLaunchUUID` in the test bundle's `Info.plist` — real-device farms never
///    deliver environment variables to the test process, so the compiled-in plist is the
///    only channel that reaches every shard.
/// 3. A fresh UUID for this process — local runs get their own launch.
enum LaunchUUID {

    private static let lock = NSLock()
    private static var resolvedValue: String?
    private static var resolvedSource: LaunchUUIDSource = .generated

    /// Resolve the launch UUID once. Later calls return the same value and ignore `testBundle`.
    @discardableResult
    static func resolve(from testBundle: Bundle?) -> String {
        lock.lock()
        defer { lock.unlock() }

        if let resolvedValue = resolvedValue {
            return resolvedValue
        }

        let (value, source) = configuredLaunchUUID(from: testBundle) ?? (UUID().uuidString, .generated)
        resolvedValue = value
        resolvedSource = source
        return value
    }

    /// The resolved launch UUID. `resolve(from:)` runs first, from `testBundleWillStart`.
    static var value: String {
        resolve(from: nil)
    }

    /// Where `value` came from — read after resolution.
    static var source: LaunchUUIDSource {
        _ = value
        lock.lock()
        defer { lock.unlock() }
        return resolvedSource
    }

    /// The externally supplied launch UUID, if any: (1) `RP_LAUNCH_UUID` env var,
    /// (2) `ReportPortalLaunchUUID` in the test bundle's `Info.plist`. Whitespace-only
    /// values are treated as absent, so an unexpanded build setting does not become the
    /// launch id. Static and pure so it can be unit-tested.
    static func configuredLaunchUUID(from testBundle: Bundle?) -> (String, LaunchUUIDSource)? {
        if let value = nonEmpty(ProcessInfo.processInfo.environment["RP_LAUNCH_UUID"]) {
            return (value, .environment)
        }
        if let value = nonEmpty(testBundle?.object(forInfoDictionaryKey: "ReportPortalLaunchUUID") as? String) {
            return (value, .infoPlist)
        }
        return nil
    }

    /// The item uuid a shared container gets in every process of the run: a SHA-1 name-based
    /// UUID (version 5 layout) of the launch UUID and the container's name. Shards and retries on
    /// other devices compute the same id, so they report into one suite instead of each
    /// creating its own copy.
    static func sharedItemUUID(launchUUID: String, name: String) -> String {
        var bytes = Array(Insecure.SHA1.hash(data: Data("\(launchUUID)/\(name)".utf8)).prefix(16))
        bytes[6] = (bytes[6] & 0x0F) | 0x50 // version 5
        bytes[8] = (bytes[8] & 0x3F) | 0x80 // RFC 4122 variant
        return bytes.withUnsafeBytes { UUID(uuid: $0.load(as: uuid_t.self)) }.uuidString.lowercased()
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
              !trimmed.isEmpty else { return nil }
        return trimmed
    }
}
