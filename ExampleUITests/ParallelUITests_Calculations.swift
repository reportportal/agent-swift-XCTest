//
//  ParallelUITests_Calculations.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite C: Calculation Result Tests
/// Tests concurrent calculation verification and result field updates
final class ParallelUITests_Calculations: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        Thread.sleep(forTimeInterval: 0.5)
    }

    override func tearDown() {
        super.tearDown()
    }

    // MARK: - Basic Addition Tests

    func test01_AddTwoSmallNumbers() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("2")

        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(resultField.value as? String, "5", "2 + 3 should equal 5")
    }

    func test02_AddTenAndFive() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("10")

        secondField.tap()
        secondField.typeText("5")

        XCTAssertEqual(resultField.value as? String, "15", "10 + 5 should equal 15")
    }

    func test03_AddZeroAndNumber() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("0")

        secondField.tap()
        secondField.typeText("7")

        XCTAssertEqual(resultField.value as? String, "7", "0 + 7 should equal 7")
    }

    func test04_AddNumberAndZero() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("9")

        secondField.tap()
        secondField.typeText("0")

        XCTAssertEqual(resultField.value as? String, "9", "9 + 0 should equal 9")
    }

    func test05_AddZeroAndZero() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("0")

        secondField.tap()
        secondField.typeText("0")

        XCTAssertEqual(resultField.value as? String, "0", "0 + 0 should equal 0")
    }

    // MARK: - Two-Digit Addition Tests

    func test06_AddTwoDigitNumbers() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("13")

        secondField.tap()
        secondField.typeText("29")

        XCTAssertEqual(resultField.value as? String, "42", "13 + 29 should equal 42")
    }

    func test07_AddFiftyAndThirty() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("50")

        secondField.tap()
        secondField.typeText("30")

        XCTAssertEqual(resultField.value as? String, "80", "50 + 30 should equal 80")
    }

    func test08_AddTwentyFiveAndTwentyFive() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("25")

        secondField.tap()
        secondField.typeText("25")

        XCTAssertEqual(resultField.value as? String, "50", "25 + 25 should equal 50")
    }

    func test09_AddNinetyAndTen() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("90")

        secondField.tap()
        secondField.typeText("10")

        XCTAssertEqual(resultField.value as? String, "100", "90 + 10 should equal 100")
    }

    func test10_AddFortyTwoAndEight() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("42")

        secondField.tap()
        secondField.typeText("8")

        XCTAssertEqual(resultField.value as? String, "50", "42 + 8 should equal 50")
    }

    // MARK: - Three-Digit Addition Tests

    func test11_AddThreeDigitNumbers() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("123")

        secondField.tap()
        secondField.typeText("456")

        XCTAssertEqual(resultField.value as? String, "579", "123 + 456 should equal 579")
    }

    func test12_AddHundredAndTwoHundred() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("100")

        secondField.tap()
        secondField.typeText("200")

        XCTAssertEqual(resultField.value as? String, "300", "100 + 200 should equal 300")
    }

    func test13_AddLargeNumbers() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("555")

        secondField.tap()
        secondField.typeText("444")

        XCTAssertEqual(resultField.value as? String, "999", "555 + 444 should equal 999")
    }

    func test14_AddThreeHundredAndSevenHundred() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("300")

        secondField.tap()
        secondField.typeText("700")

        XCTAssertEqual(resultField.value as? String, "1000", "300 + 700 should equal 1000")
    }

    func test15_AddNineHundredAndOne() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("900")

        secondField.tap()
        secondField.typeText("1")

        XCTAssertEqual(resultField.value as? String, "901", "900 + 1 should equal 901")
    }

    // MARK: - Result Field Update Tests

    func test16_ResultUpdatesImmediately() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("1")

        XCTAssertEqual(resultField.value as? String, "1", "Result should update after first field")

        secondField.tap()
        secondField.typeText("1")

        XCTAssertEqual(resultField.value as? String, "2", "Result should update after second field")
    }

    func test17_ResultPersistsAcrossFocusChanges() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("5")

        secondField.tap()
        secondField.typeText("5")

        let initialResult = resultField.value as? String

        firstField.tap()

        XCTAssertEqual(resultField.value as? String, initialResult, "Result should persist across focus changes")
    }

    func test18_MultipleCalculations() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("10")

        secondField.tap()
        secondField.typeText("10")

        XCTAssertEqual(resultField.value as? String, "20", "First calculation correct")
    }

    func test19_SequentialUpdates() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("3")

        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(resultField.value as? String, "6", "Result correct after sequential updates")
    }

    func test20_ComplexCalculation() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("8")

        secondField.tap()
        secondField.typeText("7")

        XCTAssertEqual(resultField.value as? String, "15", "8 + 7 should equal 15")

        XCTAssertTrue(resultField.exists, "Result field should still exist")
    }
}
