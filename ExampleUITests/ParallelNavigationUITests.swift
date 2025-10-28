//
//  ParallelNavigationUITests.swift
//  ExampleUITests
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import XCTest

/// UI Test Suite A: Navigation and UI Element Interaction Tests
/// Tests concurrent UI navigation, element visibility, and interaction patterns
final class ParallelNavigationUITests: XCTestCase {

    private let app = XCUIApplication()

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app.launch()

        // Add small delay to ensure UI is ready
        Thread.sleep(forTimeInterval: 0.5)
    }

    // MARK: - Window and Container Tests

    func test01_WindowExistence() {
        Thread.sleep(forTimeInterval: 0.3)
        let windows = app.windows
        XCTAssertGreaterThan(windows.count, 0, "App should have at least one window")
        XCTAssertTrue(app.exists, "App should be running")
    }

    func test02_MainViewContainerExists() {
        Thread.sleep(forTimeInterval: 0.3)
        let otherElements = app.otherElements
        XCTAssertGreaterThan(otherElements.count, 0, "App should have UI container elements")
    }

    func test03_TextFieldsAreAccessible() {
        Thread.sleep(forTimeInterval: 0.3)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        XCTAssertTrue(firstField.isHittable, "First field should be accessible")
        XCTAssertTrue(secondField.isHittable, "Second field should be accessible")
        XCTAssertTrue(resultField.isHittable, "Result field should be accessible")
    }

    func test04_TextFieldCount() {
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(app.textFields.count, 3, "Should have exactly 3 text fields")
    }

    func test05_AppState() {
        Thread.sleep(forTimeInterval: 0.3)
        XCTAssertEqual(app.state, .runningForeground, "App should be in foreground")
    }

    // MARK: - Field Visibility Tests

    func test06_FirstFieldVisible() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        XCTAssertTrue(firstField.exists, "First field should exist")
        XCTAssertTrue(firstField.isEnabled, "First field should be enabled")
    }

    func test07_SecondFieldVisible() {
        Thread.sleep(forTimeInterval: 0.35)
        let secondField = app.textFields.element(boundBy: 1)
        XCTAssertTrue(secondField.exists, "Second field should exist")
        XCTAssertTrue(secondField.isEnabled, "Second field should be enabled")
    }

    func test08_ResultFieldVisible() {
        Thread.sleep(forTimeInterval: 0.35)
        let resultField = app.textFields.element(boundBy: 2)
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertTrue(resultField.isEnabled, "Result field should be enabled")
    }

    func test09_AllFieldsExistSimultaneously() {
        Thread.sleep(forTimeInterval: 0.35)
        let fields = app.textFields
        XCTAssertEqual(fields.count, 3, "All 3 fields should exist simultaneously")
    }

    func test10_FieldOrderIsCorrect() {
        Thread.sleep(forTimeInterval: 0.35)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)

        XCTAssertTrue(firstField.exists, "First field in correct position")
        XCTAssertTrue(secondField.exists, "Second field in correct position")
        XCTAssertTrue(resultField.exists, "Result field in correct position")
    }

    // MARK: - Tap and Focus Tests

    func test11_FirstFieldTapResponse() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        XCTAssertTrue(firstField.exists, "Field should still exist after tap")
    }

    func test12_SecondFieldTapResponse() {
        Thread.sleep(forTimeInterval: 0.4)
        let secondField = app.textFields.element(boundBy: 1)
        secondField.tap()
        XCTAssertTrue(secondField.exists, "Field should still exist after tap")
    }

    func test13_DoubleTapResponse() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("100")
        firstField.doubleTap()
        XCTAssertTrue(firstField.exists, "Field should exist after double tap")
    }

    func test14_SequentialFieldTaps() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)

        firstField.tap()
        XCTAssertTrue(firstField.exists, "First field tap successful")

        secondField.tap()
        XCTAssertTrue(secondField.exists, "Second field tap successful")
    }

    func test15_FocusSwitching() {
        Thread.sleep(forTimeInterval: 0.4)
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)

        firstField.tap()
        firstField.typeText("5")

        secondField.tap()
        secondField.typeText("3")

        XCTAssertEqual(firstField.value as? String, "5", "First field retains value after focus switch")
        XCTAssertEqual(secondField.value as? String, "3", "Second field has new value")
    }

    // MARK: - UI Hierarchy Tests

    func test16_WindowHierarchy() {
        Thread.sleep(forTimeInterval: 0.45)
        let window = app.windows.firstMatch
        XCTAssertTrue(window.exists, "Main window should exist in hierarchy")
    }

    func test17_DescendantElements() {
        Thread.sleep(forTimeInterval: 0.45)
        let descendants = app.descendants(matching: .any)
        XCTAssertGreaterThan(descendants.count, 3, "App should have multiple descendant elements")
    }

    func test18_TextFieldChildren() {
        Thread.sleep(forTimeInterval: 0.45)
        let textFields = app.descendants(matching: .textField)
        XCTAssertEqual(textFields.count, 3, "Should find 3 text fields in hierarchy")
    }

    func test19_ElementQueryCount() {
        Thread.sleep(forTimeInterval: 0.45)
        let allElements = app.descendants(matching: .any).count
        XCTAssertGreaterThan(allElements, 5, "Should have multiple UI elements")
    }

    func test20_UIElementTypes() {
        Thread.sleep(forTimeInterval: 0.45)
        let textFields = app.textFields.count
        let windows = app.windows.count

        XCTAssertEqual(textFields, 3, "Should have 3 text fields")
        XCTAssertGreaterThanOrEqual(windows, 1, "Should have at least 1 window")
    }
}
