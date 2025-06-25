//
//  SummatorControllerTests.swift
//  SummatorControllerTests
//
//  Created by Stas Kirichok on 28-08-2018.
//  Copyright © 2018 Windmill. All rights reserved.
//

import XCTest

class SummatorControllerTests: XCTestCase {
  
  private let app = XCUIApplication()
        
    override func setUp() {
        super.setUp()
        
        // Put setup code here. This method is called before the invocation of each test method in the class.
        
        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false
        // UI tests must launch the application that they test. Doing this in setup will make sure it happens for each test method.
        app.launch()
    }
    
    override func tearDown() {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
        super.tearDown()
    }
    
    func testOnePlusOneIsTwo() {
      let firstField = app.textFields.element(boundBy: 0)
      let secondField = app.textFields.element(boundBy: 1)
      firstField.tap()
      app.keys["1"].tap()
      app.keys["3"].tap()
      
      secondField.tap()
      app.keys["2"].tap()
      app.keys["9"].tap()
      
      let resultField = app.textFields.element(boundBy: 2)
      XCTAssertTrue(resultField.exists, "Text field doesn't exist")
      XCTAssertEqual(resultField.value as! String, "42", "Text field value is not correct")
    }
    
    // ✅ PASSING: Simple addition test
    func testSimpleAddition() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 5 + 3 = 8
        firstField.tap()
        app.keys["5"].tap()
        
        secondField.tap()
        app.keys["3"].tap()
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertEqual(resultField.value as! String, "8", "5 + 3 should equal 8")
    }
    
    // ❌ FAILING: Intentionally wrong expected result
    func testAdditionWithWrongExpectation() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 10 + 5 = 15, but expect 20 (will fail)
        firstField.tap()
        app.keys["1"].tap()
        app.keys["0"].tap()
        
        secondField.tap()
        app.keys["5"].tap()
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertEqual(resultField.value as! String, "20", "This test is designed to fail - expecting wrong result")
    }
    
    // ✅ PASSING: Zero addition test
    func testZeroAddition() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 0 + 7 = 7
        firstField.tap()
        app.keys["0"].tap()
        
        secondField.tap()
        app.keys["7"].tap()
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertEqual(resultField.value as! String, "7", "0 + 7 should equal 7")
    }
    
    // ❌ FAILING: Test non-existent UI element
    func testNonExistentButton() {
        // This test will fail because we're looking for a button that doesn't exist
        let nonExistentButton = app.buttons["Calculate"]
        XCTAssertTrue(nonExistentButton.exists, "This test is designed to fail - button doesn't exist")
    }
    
    // ✅ PASSING: Test field existence
    func testAllTextFieldsExist() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        XCTAssertTrue(firstField.exists, "First input field should exist")
        XCTAssertTrue(secondField.exists, "Second input field should exist")
        XCTAssertTrue(resultField.exists, "Result field should exist")
        XCTAssertEqual(app.textFields.count, 3, "Should have exactly 3 text fields")
    }
    
    // ❌ FAILING: Test with assertion that will timeout
    func testFieldAccessibilityWithTimeout() {
        let firstField = app.textFields.element(boundBy: 0)
        
        // This will timeout because we're looking for a property that doesn't exist
        firstField.tap()
        app.keys["9"].tap()
        
        // This assertion will fail - looking for wrong accessibility identifier
        let nonExistentField = app.textFields["SomeWrongIdentifier"]
        XCTAssertTrue(nonExistentField.waitForExistence(timeout: 2), "This test is designed to fail - wrong identifier")
    }
    
}
