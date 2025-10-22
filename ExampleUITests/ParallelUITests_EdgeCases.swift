//
//  ParallelUITests_EdgeCases.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite E: Edge Cases and Error Scenarios
/// Tests concurrent error handling, edge cases, and boundary conditions
/// Includes intentionally failing tests to validate error reporting
final class ParallelUITests_EdgeCases: XCTestCase {

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

    // MARK: - Boundary Value Tests (Passing)

    func test01_MaximumInputLength() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("9999999999")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 > 0, "Handles maximum input length")
    }

    func test02_MinimumValidInput() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("1")
        XCTAssertEqual(firstField.value as? String, "1", "Handles minimum valid input")
    }

    func test03_RepeatedZeros() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("0000")
        XCTAssertTrue((firstField.value as? String)?.contains("0") ?? false, "Handles repeated zeros")
    }

    func test04_SingleCharacterInput() {
        Thread.sleep(forTimeInterval: 0.3)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        secondField.typeText("9")
        XCTAssertEqual(secondField.value as? String, "9", "Handles single character")
    }

    func test05_LongNumberSequence() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("123456789")
        XCTAssertTrue((firstField.value as? String)?.count ?? 0 >= 9, "Handles long sequences")
    }

    // MARK: - Element Query Edge Cases (Passing)

    func test06_FieldExistsCheck() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstField.exists, "Field exists check succeeds")
    }

    func test07_FieldIsEnabledCheck() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstField.isEnabled, "Field enabled check succeeds")
    }

    func test08_FieldIsHittableCheck() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstField.isHittable, "Field hittable check succeeds")
    }

    func test09_MultipleFieldsExistCheck() {
        Thread.sleep(forTimeInterval: 0.35)
        let count = app.textFields.count
        XCTAssertGreaterThanOrEqual(count, 3, "Multiple fields exist")
    }

    func test10_AppIsRunningCheck() {
        Thread.sleep(forTimeInterval: 0.35)
        XCTAssertEqual(app.state, .runningForeground, "App is running in foreground")
    }

    // MARK: - Intentionally Failing Tests (For Error Reporting Validation)

    func test11_WrongExpectedValue_FAILS() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("10")

        secondField.tap()
        secondField.typeText("5")

        // This will FAIL - expecting wrong result
        XCTAssertEqual(resultField.value as? String, "20", "❌ INTENTIONAL FAILURE: Expected 20, actual is 15")
    }

    func test12_NonExistentElement_FAILS() {
        Thread.sleep(forTimeInterval: 0.4)
        // This will FAIL - looking for non-existent button
        let nonExistentButton = app.buttons["CalculateButton"]
        XCTAssertTrue(nonExistentButton.exists, "❌ INTENTIONAL FAILURE: Button doesn't exist")
    }

    func test13_WrongFieldIndex_FAILS() {
        Thread.sleep(forTimeInterval: 0.4)
        // This will FAIL - trying to access field at index 10
        let nonExistentField = app.textFields.element(boundBy: 10)
        XCTAssertTrue(nonExistentField.exists, "❌ INTENTIONAL FAILURE: Index out of bounds")
    }

    func test14_WrongAccessibilityIdentifier_FAILS() {
        Thread.sleep(forTimeInterval: 0.4)
        // This will FAIL - wrong identifier with timeout
        let field = app.textFields["NonExistentIdentifier"]
        XCTAssertTrue(field.waitForExistence(timeout: 1), "❌ INTENTIONAL FAILURE: Wrong accessibility ID")
    }

    func test15_NilValueAssertion_FAILS() {
        Thread.sleep(forTimeInterval: 0.4)
        let resultField = app.textFields.element(boundBy: 2)
        // This will FAIL - result field has value "0", not nil
        XCTAssertNil(resultField.value, "❌ INTENTIONAL FAILURE: Expected nil, has value")
    }

    // MARK: - Complex Edge Cases (Passing)

    func test16_RapidSuccessiveTaps() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)

        for _ in 1...5 {
            firstField.tap()
        }

        XCTAssertTrue(firstField.exists, "Handles rapid successive taps")
    }

    func test17_TypeWithoutInitialTap() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)

        // Tap and type immediately
        firstField.tap()
        firstField.typeText("42")

        XCTAssertEqual(firstField.value as? String, "42", "Typing works after tap")
    }

    func test18_FieldPersistenceCheck() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)

        let exists1 = firstField.exists

        firstField.tap()
        firstField.typeText("100")

        let exists2 = firstField.exists

        XCTAssertEqual(exists1, exists2, "Field existence persists through interaction")
    }

    func test19_AllFieldsAfterHeavyInteraction() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        firstField.tap()
        firstField.typeText("999")

        secondField.tap()
        secondField.typeText("888")

        XCTAssertTrue(firstField.exists && secondField.exists && resultField.exists, "All fields exist after heavy interaction")
    }

    func test20_StateConsistencyAfterErrors() {
        Thread.sleep(forTimeInterval: 0.45)
        let firstField = app.textFields.element(boundBy: 0)

        // Perform valid operations
        firstField.tap()
        firstField.typeText("5")

        // Check state remains consistent
        XCTAssertTrue(firstField.exists, "Field exists after operations")
        XCTAssertTrue(firstField.isEnabled, "Field enabled after operations")
        XCTAssertTrue(firstField.isHittable, "Field hittable after operations")
    }
}
