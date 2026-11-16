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

/// Represents an isolated execution context for a single test case.
/// Immutable value type ensures no shared state between concurrent tests.
struct TestOperation: Sendable {
    /// Unique identifier for tracing this test's lifecycle across logs
    let correlationID: UUID

    /// ReportPortal item ID for this test case (mutable to set after API call)
    var testID: String

    /// Parent suite ID (for hierarchy)
    let suiteID: String

    /// XCTest test method name (e.g., "testExample")
    let testName: String

    /// Current status (.passed, .failed, .skipped, etc.) - nil if test hasn't started
    var status: TestStatus?

    /// Stable identity sent to ReportPortal (`Module.Class.method`).
    var codeRef: String?

    /// Item attributes, e.g. the device a test ran on in a shared launch.
    var attributes: [[String: String]] = []

    /// Ask ReportPortal to nest an earlier attempt of this test under this one.
    var retry = false

    /// Initialize a new test operation
    init(
        correlationID: UUID = UUID(),
        testID: String,
        suiteID: String,
        testName: String,
        status: TestStatus? = nil
    ) {
        self.correlationID = correlationID
        self.testID = testID
        self.suiteID = suiteID
        self.testName = testName
        self.status = status
    }
}
