//
//  ParallelDataEntryUITests.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite B: Data Entry and Input Validation Tests
/// Tests concurrent text input, keyboard interaction, and field value updates
final class ParallelDataEntryUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Single Digit Entry Tests

    func test01_EnterSingleDigitInFirstField() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("7")
        XCTAssertEqual(firstField.value as? String, "7", "Should display single digit")
    }

    func test02_EnterSingleDigitInSecondField() {
        Thread.sleep(forTimeInterval: 0.3)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("9")
        XCTAssertEqual(secondField.value as? String, "9", "Should display single digit")
    }

    func test03_EnterZero() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("0")
        XCTAssertEqual(firstField.value as? String, "0", "Should handle zero input")
    }

    func test04_EnterNine() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("9")
        XCTAssertEqual(firstField.value as? String, "9", "Should handle nine input")
    }

    func test05_EnterFive() {
        Thread.sleep(forTimeInterval: 0.3)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("5")
        XCTAssertEqual(secondField.value as? String, "5", "Should handle five input")
    }

    // MARK: - Multi-Digit Entry Tests

    func test06_EnterTwoDigits() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("42")
        XCTAssertEqual(firstField.value as? String, "42", "Should display two digits")
    }

    func test07_EnterThreeDigits() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("123")
        XCTAssertEqual(firstField.value as? String, "123", "Should display three digits")
    }

    func test08_EnterFourDigits() {
        Thread.sleep(forTimeInterval: 0.35)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("9876")
        XCTAssertEqual(secondField.value as? String, "9876", "Should display four digits")
    }

    func test09_EnterLargeNumber() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("12345")
        XCTAssertEqual(firstField.value as? String, "12345", "Should handle large numbers")
    }

    func test10_EnterSequentialNumbers() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("1234567890")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 > 0, "Should accept sequential input")
    }

    // MARK: - Rapid Entry Tests

    func test11_RapidTyping() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("111")
        XCTAssertEqual(firstField.value as? String, "111", "Should handle rapid typing")
    }

    func test12_AlternatingFields() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)

        firstField.tap()
        firstField.typeText("1")

        secondField.tap()
        secondField.typeText("2")

        XCTAssertEqual(firstField.value as? String, "1", "First field retains value")
        XCTAssertEqual(secondField.value as? String, "2", "Second field has value")
    }

    func test13_BackAndForthEntry() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)

        firstField.tap()
        firstField.typeText("10")

        secondField.tap()
        secondField.typeText("20")

        firstField.tap()
        firstField.typeText("5")

        XCTAssertEqual(firstField.value as? String, "105", "Should append to first field")
    }

    func test14_MultipleFieldUpdates() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)

        firstField.tap()
        firstField.typeText("7")

        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(firstField.value as? String, "7", "First field value correct")
        XCTAssertEqual(secondField.value as? String, "3", "Second field value correct")
    }

    func test15_ClearAndReenter() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)

        firstField.tap()
        firstField.typeText("99")
        firstField.doubleTap()
        firstField.typeText("11")

        XCTAssertTrue((firstField.value as? String)?.contains("11") ?? false, "Field should contain new value")
    }

    // MARK: - Special Number Tests

    func test16_EnterRepeatingDigits() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("777")
        XCTAssertEqual(firstField.value as? String, "777", "Should handle repeating digits")
    }

    func test17_EnterSequentialDigits() {
        Thread.sleep(forTimeInterval: 0.45)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("123")
        XCTAssertEqual(secondField.value as? String, "123", "Should handle sequential digits")
    }

    func test18_EnterReverseSequence() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("321")
        XCTAssertEqual(firstField.value as? String, "321", "Should handle reverse sequence")
    }

    func test19_EnterAlternatingDigits() {
        Thread.sleep(forTimeInterval: 0.45)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("101")
        XCTAssertEqual(secondField.value as? String, "101", "Should handle alternating digits")
    }

    func test20_EnterAllZeros() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("000")
        XCTAssertTrue((firstField.value as? String)?.contains("0") ?? false, "Should handle multiple zeros")
    }
}
