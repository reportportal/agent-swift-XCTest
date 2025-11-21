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

/// UI Test Suite B: Data Entry and Input Validation Tests
/// Tests concurrent text input, keyboard interaction, and field value updates
final class ParallelDataEntryUITests: XCTestCase {

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

    // MARK: - Single Digit Entry Tests

    func test01_EnterSingleDigitInFirstField() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("7")
        waitForElementValue(firstField, toEqual: "7", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "7", "Should display single digit")
    }

    func test02_EnterSingleDigitInSecondField() {
        waitForElementToBeHittable(secondField, timeout: 2.0)

        secondField.tap()
        secondField.typeText("9")
        waitForElementValue(secondField, toEqual: "9", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "9", "Should display single digit")
    }

    func test03_EnterZero() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("0")
        waitForElementValue(firstField, toEqual: "0", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "0", "Should handle zero input")
    }

    func test04_EnterNine() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("9")
        waitForElementValue(firstField, toEqual: "9", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "9", "Should handle nine input")
    }

    func test05_EnterFive() {
        waitForElementToBeHittable(secondField, timeout: 2.0)

        secondField.tap()
        secondField.typeText("5")
        waitForElementValue(secondField, toEqual: "5", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "5", "Should handle five input")
    }

    // MARK: - Multi-Digit Entry Tests

    func test06_EnterTwoDigits() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("42")
        waitForElementValue(firstField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "42", "Should display two digits")
    }

    func test07_EnterThreeDigits() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("123")
        waitForElementValue(firstField, toEqual: "123", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "123", "Should display three digits")
    }

    func test08_EnterFourDigits() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("9876")
        waitForElementValue(secondField, toEqual: "9876", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "9876", "Should display four digits")
    }

    func test09_EnterLargeNumber() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("12345")
        waitForElementValue(firstField, toEqual: "12345", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "12345", "Should handle large numbers")
    }

    func test10_EnterSequentialNumbers() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("1234567890")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 > 0, "Should accept sequential input")
    }

    // MARK: - Rapid Entry Tests

    func test11_RapidTyping() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("111")
        waitForElementValue(firstField, toEqual: "111", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "111", "Should handle rapid typing")
    }

    func test12_AlternatingFields() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("1")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("2")

        waitForElementValue(firstField, toEqual: "1", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "1", "First field retains value")
        waitForElementValue(secondField, toEqual: "2", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "2", "Second field has value")
    }

    func test13_BackAndForthEntry() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("10")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("20")

        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("5")

        waitForElementValue(firstField, toEqual: "105", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "105", "Should append to first field")
    }

    func test14_MultipleFieldUpdates() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("7")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")

        waitForElementValue(firstField, toEqual: "7", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "7", "First field value correct")
        waitForElementValue(secondField, toEqual: "3", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "3", "Second field value correct")
    }

    func test15_ClearAndReenter() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("99")
        firstField.doubleTap()
        firstField.typeText("11")

        XCTAssertTrue((firstField.value as? String)?.contains("11") ?? false, "Field should contain new value")
    }

    // MARK: - Special Number Tests

    func test16_EnterRepeatingDigits() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("777")
        waitForElementValue(firstField, toEqual: "777", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "777", "Should handle repeating digits")
    }

    func test17_EnterSequentialDigits() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("123")
        waitForElementValue(secondField, toEqual: "123", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "123", "Should handle sequential digits")
    }

    func test18_EnterReverseSequence() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("321")
        waitForElementValue(firstField, toEqual: "321", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "321", "Should handle reverse sequence")
    }

    func test19_EnterAlternatingDigits() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("101")
        waitForElementValue(secondField, toEqual: "101", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "101", "Should handle alternating digits")
    }

    func test20_EnterAllZeros() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("000")
        XCTAssertTrue((firstField.value as? String)?.contains("0") ?? false, "Should handle multiple zeros")
    }
}
