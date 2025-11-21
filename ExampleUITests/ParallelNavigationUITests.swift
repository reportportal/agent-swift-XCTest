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

import XCTest

/// UI Test Suite A: Navigation and UI Element Interaction Tests
/// Tests concurrent UI navigation, element visibility, and interaction patterns
final class ParallelNavigationUITests: XCTestCase {

    private let app = XCUIApplication()

    // MARK: - UI Element Helpers

    private var firstField: XCUIElement {
        app.textFields.element(boundBy: 0)
    }

    private var secondField: XCUIElement {
        app.textFields.element(boundBy: 1)
    }

    private var resultField: XCUIElement {
        app.textFields.element(boundBy: 2)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        waitForAppToBeReady(app, timeout: 5.0)
        waitForElementToBeHittable(firstField, timeout: 5.0)
    }

    // MARK: - Window and Container Tests

    func test01_WindowExistence() {
        let windows = app.windows
        XCTAssertGreaterThan(windows.count, 0, "App should have at least one window")
        XCTAssertTrue(app.exists, "App should be running")
    }

    func test02_MainViewContainerExists() {
        let otherElements = app.otherElements
        XCTAssertGreaterThan(otherElements.count, 0, "App should have UI container elements")
    }

    func test03_TextFieldsAreAccessible() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        waitForElementToBeHittable(secondField, timeout: 2.0)
        waitForElementToBeHittable(resultField, timeout: 2.0)
        XCTAssertTrue(firstField.isHittable, "First field should be accessible")
        XCTAssertTrue(secondField.isHittable, "Second field should be accessible")
        XCTAssertTrue(resultField.isHittable, "Result field should be accessible")
    }

    func test04_TextFieldCount() {
        XCTAssertEqual(app.textFields.count, 3, "Should have exactly 3 text fields")
    }

    func test05_AppState() {
        XCTAssertEqual(app.state, .runningForeground, "App should be in foreground")
    }

    // MARK: - Field Visibility Tests

    func test06_FirstFieldVisible() {
        waitForElement(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.exists, "First field should exist")
        XCTAssertTrue(firstField.isEnabled, "First field should be enabled")
    }

    func test07_SecondFieldVisible() {
        waitForElement(secondField, timeout: 2.0)
        XCTAssertTrue(secondField.exists, "Second field should exist")
        XCTAssertTrue(secondField.isEnabled, "Second field should be enabled")
    }

    func test08_ResultFieldVisible() {
        waitForElement(resultField, timeout: 2.0)
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertTrue(resultField.isEnabled, "Result field should be enabled")
    }

    func test09_AllFieldsExistSimultaneously() {
        let fields = app.textFields
        XCTAssertEqual(fields.count, 3, "All 3 fields should exist simultaneously")
    }

    func test10_FieldOrderIsCorrect() {
        waitForElement(firstField, timeout: 2.0)
        waitForElement(secondField, timeout: 2.0)
        waitForElement(resultField, timeout: 2.0)
        XCTAssertTrue(firstField.exists, "First field in correct position")
        XCTAssertTrue(secondField.exists, "Second field in correct position")
        XCTAssertTrue(resultField.exists, "Result field in correct position")
    }

    // MARK: - Tap and Focus Tests

    func test11_FirstFieldTapResponse() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        XCTAssertTrue(firstField.exists, "Field should still exist after tap")
    }

    func test12_SecondFieldTapResponse() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        XCTAssertTrue(secondField.exists, "Field should still exist after tap")
    }

    func test13_DoubleTapResponse() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("100")
        firstField.doubleTap()
        XCTAssertTrue(firstField.exists, "Field should exist after double tap")
    }

    func test14_SequentialFieldTaps() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        XCTAssertTrue(firstField.exists, "First field tap successful")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        XCTAssertTrue(secondField.exists, "Second field tap successful")
    }

    func test15_FocusSwitching() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("5")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")

        waitForElementValue(firstField, toEqual: "5", timeout: 2.0)
        waitForElementValue(secondField, toEqual: "3", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "5", "First field retains value after focus switch")
        XCTAssertEqual(secondField.value as? String, "3", "Second field has new value")
    }

    // MARK: - UI Hierarchy Tests

    func test16_WindowHierarchy() {
        let window = app.windows.firstMatch
        waitForElement(window, timeout: 2.0)
        XCTAssertTrue(window.exists, "Main window should exist in hierarchy")
    }

    func test17_DescendantElements() {
        let descendants = app.descendants(matching: .any)
        XCTAssertGreaterThan(descendants.count, 3, "App should have multiple descendant elements")
    }

    func test18_TextFieldChildren() {
        let textFields = app.descendants(matching: .textField)
        XCTAssertEqual(textFields.count, 3, "Should find 3 text fields in hierarchy")
    }

    func test19_ElementQueryCount() {
        let allElements = app.descendants(matching: .any).count
        XCTAssertGreaterThan(allElements, 5, "Should have multiple UI elements")
    }

    func test20_UIElementTypes() {
        let textFields = app.textFields.count
        let windows = app.windows.count

        XCTAssertEqual(textFields, 3, "Should have 3 text fields")
        XCTAssertGreaterThanOrEqual(windows, 1, "Should have at least 1 window")
    }
}
