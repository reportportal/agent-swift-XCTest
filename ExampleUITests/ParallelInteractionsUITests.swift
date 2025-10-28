//
//  ParallelInteractionsUITests.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
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
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Multi-Step Interaction Tests

    func test01_TapTypeCheckSequence() {
        Thread.sleep(forTimeInterval: 0.3)

        firstField.tap()
        XCTAssertTrue(firstField.exists, "Field exists after tap")

        firstField.typeText("42")
        XCTAssertEqual(firstField.value as? String, "42", "Value correct after typing")

        XCTAssertTrue(firstField.isHittable, "Field still accessible after interaction")
    }

    func test02_CompleteAdditionWorkflow() {
        Thread.sleep(forTimeInterval: 0.3)
        firstField.tap()
        firstField.typeText("15")

        secondField.tap()
        secondField.typeText("27")

        XCTAssertEqual(resultField.value as? String, "42", "Complete workflow successful")
    }

    func test03_MultipleFieldInteractionCycle() {
        Thread.sleep(forTimeInterval: 0.3)

        for i in 1...3 {
            firstField.tap()
            XCTAssertTrue(firstField.exists, "Field accessible in cycle \(i)")

            secondField.tap()
            XCTAssertTrue(secondField.exists, "Second field accessible in cycle \(i)")
        }
    }

    func test04_RapidFieldSwitching() {
        Thread.sleep(forTimeInterval: 0.3)

        firstField.tap()
        secondField.tap()
        firstField.tap()
        secondField.tap()

        XCTAssertTrue(secondField.exists, "Fields handle rapid switching")
    }

    func test05_TypeClearTypeWorkflow() {
        Thread.sleep(forTimeInterval: 0.3)

        firstField.tap()
        firstField.typeText("999")

        firstField.doubleTap()

        firstField.typeText("1")

        XCTAssertTrue((firstField.value as? String)?.contains("1") ?? false, "Clear and retype workflow works")
    }

    // MARK: - Field State Verification Tests

    func test06_FieldStatesAfterInteraction() {
        Thread.sleep(forTimeInterval: 0.35)

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
        Thread.sleep(forTimeInterval: 0.35)
        firstField.tap()
        firstField.typeText("10")

        XCTAssertTrue(secondField.isHittable, "Second field still accessible")
        XCTAssertTrue(resultField.isHittable, "Result field still accessible")
    }

    func test08_FieldCountConsistency() {
        Thread.sleep(forTimeInterval: 0.35)
        let initialCount = app.textFields.count

        firstField.tap()
        firstField.typeText("123")

        let afterCount = app.textFields.count

        XCTAssertEqual(initialCount, afterCount, "Field count remains consistent")
    }

    func test09_FieldOrderPreservation() {
        Thread.sleep(forTimeInterval: 0.35)

        firstField.tap()
        firstField.typeText("1")

        secondField.tap()
        secondField.typeText("2")

        let checkFirst = app.textFields.element(boundBy: 0)
        let checkSecond = app.textFields.element(boundBy: 1)

        XCTAssertEqual(checkFirst.value as? String, "1", "First field order preserved")
        XCTAssertEqual(checkSecond.value as? String, "2", "Second field order preserved")
    }

    func test10_StateAfterMultipleInteractions() {
        Thread.sleep(forTimeInterval: 0.35)

        firstField.tap()
        firstField.typeText("5")

        firstField.doubleTap()

        firstField.tap()
        firstField.typeText("3")

        XCTAssertTrue(firstField.exists, "Field exists after multiple interactions")
        XCTAssertTrue(firstField.isEnabled, "Field enabled after multiple interactions")
    }

    // MARK: - Parallel Interaction Tests

    func test11_SimultaneousFieldAccess() {
        Thread.sleep(forTimeInterval: 0.4)

        XCTAssertTrue(firstField.exists && secondField.exists && resultField.exists, "All fields accessible simultaneously")
    }

    func test12_CrossFieldValueCheck() {
        Thread.sleep(forTimeInterval: 0.4)

        firstField.tap()
        firstField.typeText("7")

        let firstValue = firstField.value as? String

        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(firstField.value as? String, firstValue, "First field value preserved while interacting with second")
    }

    func test13_IndependentFieldUpdates() {
        Thread.sleep(forTimeInterval: 0.4)

        firstField.tap()
        firstField.typeText("100")

        secondField.tap()
        secondField.typeText("200")

        XCTAssertEqual(firstField.value as? String, "100", "First field independent")
        XCTAssertEqual(secondField.value as? String, "200", "Second field independent")
    }

    func test14_ResultReflectsAllInputs() {
        Thread.sleep(forTimeInterval: 0.4)
        firstField.tap()
        firstField.typeText("12")

        secondField.tap()
        secondField.typeText("13")

        XCTAssertEqual(resultField.value as? String, "25", "Result reflects both inputs")
    }

    func test15_ConsecutiveCalculations() {
        Thread.sleep(forTimeInterval: 0.4)
        firstField.tap()
        firstField.typeText("5")

        secondField.tap()
        secondField.typeText("5")

        let firstResult = resultField.value as? String
        XCTAssertEqual(firstResult, "10", "First calculation correct")
    }

    // MARK: - Edge Case Interactions

    func test16_EmptyFieldInteraction() {
        Thread.sleep(forTimeInterval: 0.45)

        firstField.tap()
        // Don't type anything

        XCTAssertTrue(firstField.exists, "Field handles tap without typing")
    }

    func test17_DoubleFieldEntry() {
        Thread.sleep(forTimeInterval: 0.45)

        firstField.tap()
        firstField.typeText("1")
        firstField.typeText("2")

        XCTAssertTrue((firstField.value as? String)?.contains("12") ?? false, "Handles consecutive typing")
    }

    func test18_FieldExistsAfterLongInteraction() {
        Thread.sleep(forTimeInterval: 0.45)

        firstField.tap()
        firstField.typeText("1")
        Thread.sleep(forTimeInterval: 0.1)
        firstField.typeText("2")
        Thread.sleep(forTimeInterval: 0.1)
        firstField.typeText("3")

        XCTAssertTrue(firstField.exists, "Field exists after long interaction")
    }

    func test19_MultipleFieldsAccessibleAfterWork() {
        Thread.sleep(forTimeInterval: 0.45)

        firstField.tap()
        firstField.typeText("50")

        secondField.tap()
        secondField.typeText("25")

        XCTAssertTrue(firstField.isHittable, "First field still accessible")
        XCTAssertTrue(secondField.isHittable, "Second field still accessible")
    }

    func test20_CompleteUserJourney() {
        Thread.sleep(forTimeInterval: 0.45)

        // Step 1: Check initial state
        XCTAssertTrue(firstField.exists, "Step 1: First field exists")

        // Step 2: Enter first number
        firstField.tap()
        firstField.typeText("20")
        XCTAssertEqual(firstField.value as? String, "20", "Step 2: First value entered")

        // Step 3: Enter second number
        secondField.tap()
        secondField.typeText("22")
        XCTAssertEqual(secondField.value as? String, "22", "Step 3: Second value entered")

        // Step 4: Verify result
        XCTAssertEqual(resultField.value as? String, "42", "Step 4: Result correct")

        // Step 5: All fields still accessible
        XCTAssertTrue(firstField.isHittable && secondField.isHittable && resultField.isHittable, "Step 5: All fields accessible")
    }
}
