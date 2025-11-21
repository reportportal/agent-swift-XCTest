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

/// UI Test Suite E: Edge Cases and Error Scenarios
/// Tests concurrent error handling, edge cases, and boundary conditions
/// Includes intentionally failing tests to validate error reporting
final class ParallelEdgeCasesUITests: XCTestCase {

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

    // MARK: - Boundary Value Tests (Passing)

    func test01_MaximumInputLength() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("9999999999")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 > 0, "Handles maximum input length")
    }

    func test02_MinimumValidInput() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("1")
        waitForElementValue(firstField, toEqual: "1", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "1", "Handles minimum valid input")
    }

    func test03_RepeatedZeros() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("0000")
        XCTAssertTrue((firstField.value as? String)?.contains("0") ?? false, "Handles repeated zeros")
    }

    func test04_SingleCharacterInput() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("9")
        waitForElementValue(secondField, toEqual: "9", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "9", "Handles single character")
    }

    func test05_LongNumberSequence() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("123456789")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 >= 9, "Handles long sequences")
    }

    // MARK: - Element Query Edge Cases (Passing)

    func test06_FieldExistsCheck() {
        waitForElement(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.exists, "Field exists check succeeds")
    }

    func test07_FieldIsEnabledCheck() {
        waitForElement(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.isEnabled, "Field enabled check succeeds")
    }

    func test08_FieldIsHittableCheck() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.isHittable, "Field hittable check succeeds")
    }

    func test09_MultipleFieldsExistCheck() {
        waitForElement(firstField, timeout: 2.0)
        let count = app.textFields.count
        XCTAssertGreaterThanOrEqual(count, 3, "Multiple fields exist")
    }

    func test10_AppIsRunningCheck() {
        waitForAppToBeReady(app, timeout: 2.0)
        XCTAssertEqual(app.state, .runningForeground, "App is running in foreground")
    }

    // MARK: - Intentionally Failing Tests (For Error Reporting Validation)

    func test11_WrongExpectedValue_FAILS() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("10")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("5")

        // This will FAIL - expecting wrong result
        XCTAssertEqual(resultField.value as? String, "20", "❌ INTENTIONAL FAILURE: Expected 20, actual is 15")
    }

    func test12_NonExistentElement_FAILS() {
        waitForAppToBeReady(app, timeout: 2.0)
        // This will FAIL - looking for non-existent button
        let nonExistentButton = app.buttons["CalculateButton"]
        XCTAssertTrue(nonExistentButton.exists, "❌ INTENTIONAL FAILURE: Button doesn't exist")
    }

    func test13_WrongFieldIndex_FAILS() {
        waitForElement(firstField, timeout: 2.0)
        // This will FAIL - trying to access field at index 10
        let nonExistentField = app.textFields.element(boundBy: 10)
        XCTAssertTrue(nonExistentField.exists, "❌ INTENTIONAL FAILURE: Index out of bounds")
    }

    func test14_WrongAccessibilityIdentifier_FAILS() {
        waitForAppToBeReady(app, timeout: 2.0)
        // This will FAIL - wrong identifier with timeout
        let field = app.textFields["NonExistentIdentifier"]
        XCTAssertTrue(field.waitForExistence(timeout: 1), "❌ INTENTIONAL FAILURE: Wrong accessibility ID")
    }

    func test15_NilValueAssertion_FAILS() {
        waitForElement(resultField, timeout: 2.0)
        // This will FAIL - result field has value "0", not nil
        XCTAssertNil(resultField.value, "❌ INTENTIONAL FAILURE: Expected nil, has value")
    }

    // MARK: - Complex Edge Cases (Passing)

    func test16_RapidSuccessiveTaps() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        for _ in 1...5 {
            firstField.tap()
        }

        XCTAssertTrue(firstField.exists, "Handles rapid successive taps")
    }

    func test17_TypeWithoutInitialTap() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        // Tap and type immediately
        firstField.tap()
        firstField.typeText("42")

        waitForElementValue(firstField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "42", "Typing works after tap")
    }

    func test18_FieldPersistenceCheck() {
        waitForElement(firstField, timeout: 2.0)

        let exists1 = firstField.exists

        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("100")

        let exists2 = firstField.exists

        XCTAssertEqual(exists1, exists2, "Field existence persists through interaction")
    }

    func test19_AllFieldsAfterHeavyInteraction() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("999")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("888")

        XCTAssertTrue(firstField.exists && secondField.exists && resultField.exists, "All fields exist after heavy interaction")
    }

    func test20_StateConsistencyAfterErrors() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        // Perform valid operations
        firstField.tap()
        firstField.typeText("5")

        // Check state remains consistent
        XCTAssertTrue(firstField.exists, "Field exists after operations")
        XCTAssertTrue(firstField.isEnabled, "Field enabled after operations")
        XCTAssertTrue(firstField.isHittable, "Field hittable after operations")
    }
}
