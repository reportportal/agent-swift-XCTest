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

/// UI Test Suite D: Complex User Interactions
/// Tests concurrent complex user interaction patterns and edge cases
final class ParallelInteractionsUITests: XCTestCase {

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

    // MARK: - Multi-Step Interaction Tests

    func test01_TapTypeCheckSequence() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        XCTAssertTrue(firstField.exists, "Field exists after tap")

        firstField.typeText("42")
        waitForElementValue(firstField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "42", "Value correct after typing")

        XCTAssertTrue(firstField.isHittable, "Field still accessible after interaction")
    }

    func test02_CompleteAdditionWorkflow() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("15")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("27")

        waitForElementValue(resultField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "42", "Complete workflow successful")
    }

    func test03_MultipleFieldInteractionCycle() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        for i in 1...3 {
            waitForElementToBeHittable(firstField, timeout: 2.0)
            firstField.tap()
            XCTAssertTrue(firstField.exists, "Field accessible in cycle \(i)")

            waitForElementToBeHittable(secondField, timeout: 2.0)
            secondField.tap()
            XCTAssertTrue(secondField.exists, "Second field accessible in cycle \(i)")
        }
    }

    func test04_RapidFieldSwitching() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()

        XCTAssertTrue(secondField.exists, "Fields handle rapid switching")
    }

    func test05_TypeClearTypeWorkflow() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("999")

        firstField.doubleTap()

        firstField.typeText("1")

        XCTAssertTrue((firstField.value as? String)?.contains("1") ?? false, "Clear and retype workflow works")
    }

    // MARK: - Field State Verification Tests

    func test06_FieldStatesAfterInteraction() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        let initialExists = firstField.exists
        let initialEnabled = firstField.isEnabled
        let initialHittable = firstField.isHittable

        firstField.tap()
        firstField.typeText("5")

        XCTAssertEqual(firstField.exists, initialExists, "Exists state unchanged")
        XCTAssertEqual(firstField.isEnabled, initialEnabled, "Enabled state unchanged")
        XCTAssertEqual(firstField.isHittable, initialHittable, "Hittable state unchanged")
    }

    func test07_AllFieldsRemainAccessible() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("10")

        XCTAssertTrue(secondField.isHittable, "Second field still accessible")
        XCTAssertTrue(resultField.isHittable, "Result field still accessible")
    }

    func test08_FieldCountConsistency() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        let initialCount = app.textFields.count

        firstField.tap()
        firstField.typeText("123")

        let afterCount = app.textFields.count

        XCTAssertEqual(initialCount, afterCount, "Field count remains consistent")
    }

    func test09_FieldOrderPreservation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("1")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("2")

        let checkFirst = app.textFields.element(boundBy: 0)
        let checkSecond = app.textFields.element(boundBy: 1)

        waitForElementValue(checkFirst, toEqual: "1", timeout: 2.0)
        XCTAssertEqual(checkFirst.value as? String, "1", "First field order preserved")
        waitForElementValue(checkSecond, toEqual: "2", timeout: 2.0)
        XCTAssertEqual(checkSecond.value as? String, "2", "Second field order preserved")
    }

    func test10_StateAfterMultipleInteractions() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("5")

        firstField.doubleTap()

        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("3")

        XCTAssertTrue(firstField.exists, "Field exists after multiple interactions")
        XCTAssertTrue(firstField.isEnabled, "Field enabled after multiple interactions")
    }

    // MARK: - Parallel Interaction Tests

    func test11_SimultaneousFieldAccess() {
        waitForElement(firstField, timeout: 2.0)
        waitForElement(secondField, timeout: 2.0)
        waitForElement(resultField, timeout: 2.0)

        XCTAssertTrue(firstField.exists && secondField.exists && resultField.exists, "All fields accessible simultaneously")
    }

    func test12_CrossFieldValueCheck() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("7")

        waitForElementValue(firstField, toEqual: "7", timeout: 2.0)
        let firstValue = firstField.value as? String

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(firstField.value as? String, firstValue, "First field value preserved while interacting with second")
    }

    func test13_IndependentFieldUpdates() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("100")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("200")

        waitForElementValue(firstField, toEqual: "100", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "100", "First field independent")
        waitForElementValue(secondField, toEqual: "200", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "200", "Second field independent")
    }

    func test14_ResultReflectsAllInputs() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("12")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("13")

        waitForElementValue(resultField, toEqual: "25", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "25", "Result reflects both inputs")
    }

    func test15_ConsecutiveCalculations() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("5")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("5")

        waitForElementValue(resultField, toEqual: "10", timeout: 2.0)
        let firstResult = resultField.value as? String
        XCTAssertEqual(firstResult, "10", "First calculation correct")
    }

    // MARK: - Edge Case Interactions

    func test16_EmptyFieldInteraction() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        // Don't type anything

        XCTAssertTrue(firstField.exists, "Field handles tap without typing")
    }

    func test17_DoubleFieldEntry() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("1")
        firstField.typeText("2")

        XCTAssertTrue((firstField.value as? String)?.contains("12") ?? false, "Handles consecutive typing")
    }

    func test18_FieldExistsAfterLongInteraction() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("1")
        firstField.typeText("2")
        firstField.typeText("3")

        XCTAssertTrue(firstField.exists, "Field exists after long interaction")
    }

    func test19_MultipleFieldsAccessibleAfterWork() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("50")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("25")

        XCTAssertTrue(firstField.isHittable, "First field still accessible")
        XCTAssertTrue(secondField.isHittable, "Second field still accessible")
    }

    func test20_CompleteUserJourney() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        // Step 1: Check initial state
        XCTAssertTrue(firstField.exists, "Step 1: First field exists")

        // Step 2: Enter first number
        firstField.tap()
        firstField.typeText("20")
        waitForElementValue(firstField, toEqual: "20", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "20", "Step 2: First value entered")

        // Step 3: Enter second number
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("22")
        waitForElementValue(secondField, toEqual: "22", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "22", "Step 3: Second value entered")

        // Step 4: Verify result
        waitForElementValue(resultField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "42", "Step 4: Result correct")

        // Step 5: All fields still accessible
        XCTAssertTrue(firstField.isHittable && secondField.isHittable && resultField.isHittable, "Step 5: All fields accessible")
    }
}
