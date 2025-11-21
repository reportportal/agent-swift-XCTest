//  Helper extension for XCTest expectations to replace Thread.sleep
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

import XCTest

extension XCTestCase {

    /// Wait for an element to exist with a timeout
    /// - Parameters:
    ///   - element: The UI element to wait for
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    /// - Returns: True if element exists within timeout
    @discardableResult
    func waitForElement(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "exists == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for an element to become hittable (visible and accessible)
    /// - Parameters:
    ///   - element: The UI element to wait for
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    /// - Returns: True if element becomes hittable within timeout
    @discardableResult
    func waitForElementToBeHittable(_ element: XCUIElement, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "hittable == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for an element's value to match a specific value
    /// - Parameters:
    ///   - element: The UI element to check
    ///   - expectedValue: The expected value
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    /// - Returns: True if value matches within timeout
    @discardableResult
    func waitForElementValue(_ element: XCUIElement, toEqual expectedValue: String, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "value == %@", expectedValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Wait for the app to be in a stable state (ready for interaction)
    /// - Parameters:
    ///   - app: The XCUIApplication instance
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    func waitForAppToBeReady(_ app: XCUIApplication, timeout: TimeInterval = 5.0) {
        let predicate = NSPredicate(format: "state == %d", XCUIApplication.State.runningForeground.rawValue)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: app)
        _ = XCTWaiter().wait(for: [expectation], timeout: timeout)
    }

    /// Wait for a specific number of elements to exist
    /// - Parameters:
    ///   - query: The element query to check
    ///   - count: Expected number of elements
    ///   - timeout: Maximum time to wait (default: 5 seconds)
    /// - Returns: True if count matches within timeout
    @discardableResult
    func waitForElementCount(_ query: XCUIElementQuery, toEqual count: Int, timeout: TimeInterval = 5.0) -> Bool {
        let predicate = NSPredicate(format: "count == %d", count)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: query)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        return result == .completed
    }
}
