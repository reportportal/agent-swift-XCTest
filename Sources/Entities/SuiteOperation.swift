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

import Foundation

/// Represents a test suite execution context, managing hierarchy and child test relationships.
struct SuiteOperation: Sendable {
    /// Unique identifier for this suite's lifecycle
    let correlationID: UUID

    /// ReportPortal item ID for this suite (mutable to set after API call)
    var suiteID: String

    /// Parent root suite ID (nil for root)
    let rootSuiteID: String?

    /// XCTest suite name (e.g., "MyTestCase")
    let suiteName: String

    /// Aggregated status from child tests - nil if suite hasn't started
    var status: TestStatus?

    /// Suite start timestamp
    let startTime: Date

    /// ReportPortal IDs of child test cases
    var childTestIDs: [String]

    /// Device info, bundle name, etc.
    var metadata: [String: String]

    /// Initialize a new suite operation
    init(
        correlationID: UUID = UUID(),
        suiteID: String,
        rootSuiteID: String? = nil,
        suiteName: String,
        status: TestStatus? = nil,
        startTime: Date = Date(),
        childTestIDs: [String] = [],
        metadata: [String: String] = [:]
    ) {
        self.correlationID = correlationID
        self.suiteID = suiteID
        self.rootSuiteID = rootSuiteID
        self.suiteName = suiteName
        self.status = status
        self.startTime = startTime
        self.childTestIDs = childTestIDs
        self.metadata = metadata
    }
}
