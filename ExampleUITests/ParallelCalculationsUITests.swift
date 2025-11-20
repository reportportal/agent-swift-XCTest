//
//  ParallelCalculationsUITests.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite C: Calculation Result Tests
/// Tests concurrent calculation verification and result field updates
final class ParallelCalculationsUITests: XCTestCase {

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

    // MARK: - Basic Addition Tests

    func test01_AddTwoSmallNumbers() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("2")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")

        waitForElementValue(resultField, toEqual: "5", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "5", "2 + 3 should equal 5")
    }

    func test02_AddTenAndFive() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("10")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("5")

        waitForElementValue(resultField, toEqual: "15", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "15", "10 + 5 should equal 15")
    }

    func test03_AddZeroAndNumber() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("0")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("7")

        waitForElementValue(resultField, toEqual: "7", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "7", "0 + 7 should equal 7")
    }

    func test04_AddNumberAndZero() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("9")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("0")

        waitForElementValue(resultField, toEqual: "9", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "9", "9 + 0 should equal 9")
    }

    func test05_AddZeroAndZero() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("0")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("0")

        waitForElementValue(resultField, toEqual: "0", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "0", "0 + 0 should equal 0")
    }

    // MARK: - Two-Digit Addition Tests

    func test06_AddTwoDigitNumbers() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("13")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("29")

        waitForElementValue(resultField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "42", "13 + 29 should equal 42")
    }

    func test07_AddFiftyAndThirty() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("50")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("30")

        waitForElementValue(resultField, toEqual: "80", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "80", "50 + 30 should equal 80")
    }

    func test08_AddTwentyFiveAndTwentyFive() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("25")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("25")

        waitForElementValue(resultField, toEqual: "50", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "50", "25 + 25 should equal 50")
    }

    func test09_AddNinetyAndTen() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("90")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("10")

        waitForElementValue(resultField, toEqual: "100", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "100", "90 + 10 should equal 100")
    }

    func test10_AddFortyTwoAndEight() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("42")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("8")

        waitForElementValue(resultField, toEqual: "50", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "50", "42 + 8 should equal 50")
    }

    // MARK: - Three-Digit Addition Tests

    func test11_AddThreeDigitNumbers() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("123")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("456")

        waitForElementValue(resultField, toEqual: "579", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "579", "123 + 456 should equal 579")
    }

    func test12_AddHundredAndTwoHundred() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("100")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("200")

        waitForElementValue(resultField, toEqual: "300", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "300", "100 + 200 should equal 300")
    }

    func test13_AddLargeNumbers() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("555")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("444")

        waitForElementValue(resultField, toEqual: "999", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "999", "555 + 444 should equal 999")
    }

    func test14_AddThreeHundredAndSevenHundred() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("300")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("700")

        waitForElementValue(resultField, toEqual: "1000", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "1000", "300 + 700 should equal 1000")
    }

    func test15_AddNineHundredAndOne() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("900")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("1")

        waitForElementValue(resultField, toEqual: "901", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "901", "900 + 1 should equal 901")
    }

    // MARK: - Result Field Update Tests

    func test16_ResultUpdatesImmediately() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("1")

        waitForElementValue(resultField, toEqual: "1", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "1", "Result should update after first field")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("1")

        waitForElementValue(resultField, toEqual: "2", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "2", "Result should update after second field")
    }

    func test17_ResultPersistsAcrossFocusChanges() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("5")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("5")

        waitForElementValue(resultField, toEqual: "10", timeout: 2.0)
        let initialResult = resultField.value as? String

        firstField.tap()

        XCTAssertEqual(resultField.value as? String, initialResult, "Result should persist across focus changes")
    }

    func test18_MultipleCalculations() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("10")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("10")

        waitForElementValue(resultField, toEqual: "20", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "20", "First calculation correct")
    }

    func test19_SequentialUpdates() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("3")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")

        waitForElementValue(resultField, toEqual: "6", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "6", "Result correct after sequential updates")
    }

    func test20_ComplexCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)

        firstField.tap()
        firstField.typeText("8")

        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("7")

        waitForElementValue(resultField, toEqual: "15", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "15", "8 + 7 should equal 15")

        XCTAssertTrue(resultField.exists, "Result field should still exist")
    }
}
