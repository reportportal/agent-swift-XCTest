//
//  ParallelStressUITests.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite F: Stress Testing and High Volume
/// Tests system behavior under high concurrent load with many parallel tests
final class ParallelStressUITests: XCTestCase {

    private let app = XCUIApplication()

    // MARK: - UI Element Helpers

    private var firstField: XCUIElement {
        return app.textFields.element(boundBy: 0)
    }

    private var secondField: XCUIElement {
        return app.textFields.element(boundBy: 1)
    }

    private var resultField: XCUIElement {
        return app.textFields.element(boundBy: 2)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        waitForAppToBeReady(app, timeout: 5.0)
        waitForElementToBeHittable(firstField, timeout: 5.0)
    }

    // MARK: - Stress Test Series 1 (20 tests)

    func test001_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("1")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("1")
        waitForElementValue(resultField, toEqual: "2", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "2", "Stress test 001")
    }

    func test002_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("2")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("2")
        waitForElementValue(resultField, toEqual: "4", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "4", "Stress test 002")
    }

    func test003_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("3")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("3")
        waitForElementValue(resultField, toEqual: "6", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "6", "Stress test 003")
    }

    func test004_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("4")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("4")
        waitForElementValue(resultField, toEqual: "8", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "8", "Stress test 004")
    }

    func test005_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("5")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("5")
        waitForElementValue(resultField, toEqual: "10", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "10", "Stress test 005")
    }

    func test006_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("6")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("6")
        waitForElementValue(resultField, toEqual: "12", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "12", "Stress test 006")
    }

    func test007_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("7")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("7")
        waitForElementValue(resultField, toEqual: "14", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "14", "Stress test 007")
    }

    func test008_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("8")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("8")
        waitForElementValue(resultField, toEqual: "16", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "16", "Stress test 008")
    }

    func test009_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("9")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("9")
        waitForElementValue(resultField, toEqual: "18", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "18", "Stress test 009")
    }

    func test010_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("10")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("10")
        waitForElementValue(resultField, toEqual: "20", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "20", "Stress test 010")
    }

    func test011_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("11")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("11")
        waitForElementValue(resultField, toEqual: "22", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "22", "Stress test 011")
    }

    func test012_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("12")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("12")
        waitForElementValue(resultField, toEqual: "24", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "24", "Stress test 012")
    }

    func test013_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("13")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("13")
        waitForElementValue(resultField, toEqual: "26", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "26", "Stress test 013")
    }

    func test014_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("14")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("14")
        waitForElementValue(resultField, toEqual: "28", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "28", "Stress test 014")
    }

    func test015_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("15")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("15")
        waitForElementValue(resultField, toEqual: "30", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "30", "Stress test 015")
    }

    func test016_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("16")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("16")
        waitForElementValue(resultField, toEqual: "32", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "32", "Stress test 016")
    }

    func test017_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("17")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("17")
        waitForElementValue(resultField, toEqual: "34", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "34", "Stress test 017")
    }

    func test018_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("18")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("18")
        waitForElementValue(resultField, toEqual: "36", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "36", "Stress test 018")
    }

    func test019_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("19")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("19")
        waitForElementValue(resultField, toEqual: "38", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "38", "Stress test 019")
    }

    func test020_StressCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("20")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("20")
        waitForElementValue(resultField, toEqual: "40", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "40", "Stress test 020")
    }
}

/// Second stress test suite to increase concurrent load
final class ParallelUITestsStressB: XCTestCase {

    private let app = XCUIApplication()

    // MARK: - UI Element Helpers

    private var firstField: XCUIElement {
        return app.textFields.element(boundBy: 0)
    }

    private var secondField: XCUIElement {
        return app.textFields.element(boundBy: 1)
    }

    private var resultField: XCUIElement {
        return app.textFields.element(boundBy: 2)
    }

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()
        waitForAppToBeReady(app, timeout: 5.0)
        waitForElementToBeHittable(firstField, timeout: 5.0)
    }

    // MARK: - Stress Test Series 2 (20 tests)

    func test021_FieldExistence() {
        waitForElementCount(app.textFields, toEqual: 3, timeout: 2.0)
        XCTAssertEqual(app.textFields.count, 3, "Stress test 021")
    }

    func test022_FieldExistence() {
        waitForElement(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.exists, "Stress test 022")
    }

    func test023_FieldExistence() {
        waitForElement(secondField, timeout: 2.0)
        XCTAssertTrue(secondField.exists, "Stress test 023")
    }

    func test024_FieldExistence() {
        waitForElement(resultField, timeout: 2.0)
        XCTAssertTrue(resultField.exists, "Stress test 024")
    }

    func test025_AppState() {
        waitForAppToBeReady(app, timeout: 2.0)
        XCTAssertEqual(app.state, .runningForeground, "Stress test 025")
    }

    func test026_WindowCheck() {
        waitForAppToBeReady(app, timeout: 2.0)
        XCTAssertGreaterThan(app.windows.count, 0, "Stress test 026")
    }

    func test027_ElementQuery() {
        waitForElement(app, timeout: 2.0)
        XCTAssertTrue(app.exists, "Stress test 027")
    }

    func test028_FieldAccessibility() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.isHittable, "Stress test 028")
    }

    func test029_FieldEnabled() {
        waitForElement(firstField, timeout: 2.0)
        XCTAssertTrue(firstField.isEnabled, "Stress test 029")
    }

    func test030_MultipleFields() {
        waitForElementCount(app.textFields, toEqual: 3, timeout: 2.0)
        XCTAssertEqual(app.textFields.count, 3, "Stress test 030")
    }

    func test031_SimpleCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("25")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("25")
        waitForElementValue(resultField, toEqual: "50", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "50", "Stress test 031")
    }

    func test032_SimpleCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("30")
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("12")
        waitForElementValue(resultField, toEqual: "42", timeout: 2.0)
        XCTAssertEqual(resultField.value as? String, "42", "Stress test 032")
    }

    func test033_SimpleCalculation() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("99")
        waitForElementValue(firstField, toEqual: "99", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "99", "Stress test 033")
    }

    func test034_SimpleCalculation() {
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        secondField.typeText("88")
        waitForElementValue(secondField, toEqual: "88", timeout: 2.0)
        XCTAssertEqual(secondField.value as? String, "88", "Stress test 034")
    }

    func test035_ResultCheck() {
        waitForElement(resultField, timeout: 2.0)
        XCTAssertTrue(resultField.exists, "Stress test 035")
    }

    func test036_TapResponse() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        XCTAssertTrue(firstField.exists, "Stress test 036")
    }

    func test037_TypeResponse() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("77")
        waitForElementValue(firstField, toEqual: "77", timeout: 2.0)
        XCTAssertEqual(firstField.value as? String, "77", "Stress test 037")
    }

    func test038_FieldFocus() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        waitForElementToBeHittable(secondField, timeout: 2.0)
        secondField.tap()
        XCTAssertTrue(secondField.exists, "Stress test 038")
    }

    func test039_QuickInteraction() {
        waitForElementToBeHittable(firstField, timeout: 2.0)
        firstField.tap()
        firstField.typeText("1")
        XCTAssertTrue(firstField.exists, "Stress test 039")
    }

    func test040_FinalStressTest() {
        waitForElement(firstField, timeout: 2.0)
        waitForElement(secondField, timeout: 2.0)
        waitForElement(resultField, timeout: 2.0)

        XCTAssertTrue(firstField.exists && secondField.exists && resultField.exists, "Stress test 040 - All fields exist")
    }
}
