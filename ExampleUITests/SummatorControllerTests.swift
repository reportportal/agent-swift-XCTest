//  Created by Stas Kirichok on 28-08-2018.
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

final class SummatorControllerTests: XCTestCase {
  
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
    
    // ✅ PASSING: Test 13 + 29 = 42  
    func testOnePlusOneIsTwo() {
      let firstField = app.textFields.element(boundBy: 0)
      let secondField = app.textFields.element(boundBy: 1)
      firstField.tap()
      firstField.typeText("13")
      
      secondField.tap()
      secondField.typeText("29")
      
      let resultField = app.textFields.element(boundBy: 2)
      XCTAssertTrue(resultField.exists, "Text field doesn't exist")
      if let fieldValue = resultField.value as? String {
        XCTAssertEqual(fieldValue, "42", "Text field value is not correct")
      } else {
        XCTFail("Result field value is not a string")
      }
    }
    
    // ✅ PASSING: Simple addition test
    func testSimpleAddition() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 5 + 3 = 8
        firstField.tap()
        firstField.typeText("5")
        
        secondField.tap()
        secondField.typeText("3")
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        if let fieldValue = resultField.value as? String {
          XCTAssertEqual(fieldValue, "8", "5 + 3 should equal 8")
        } else {
          XCTFail("Result field value is not a string")
        }
    }
    
    // ❌ FAILING: Intentionally wrong expected result
    func testAdditionWithWrongExpectation() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 10 + 5 = 15, but expect 20 (will fail)
        firstField.tap()
        firstField.typeText("10")
        
        secondField.tap()
        secondField.typeText("5")
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        if let fieldValue = resultField.value as? String {
          XCTAssertEqual(fieldValue, "20", "This test is designed to fail - expecting wrong result")
        } else {
          XCTFail("Result field value is not a string")
        }
    }
    
    // ✅ PASSING: Zero addition test
    func testZeroAddition() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 0 + 7 = 7
        firstField.tap()
        firstField.typeText("0")
        
        secondField.tap()
        secondField.typeText("7")
        
        XCTAssertTrue(resultField.exists, "Result field should exist")
        if let fieldValue = resultField.value as? String {
          XCTAssertEqual(fieldValue, "7", "0 + 7 should equal 7")
        } else {
          XCTFail("Result field value is not a string")
        }
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
        firstField.typeText("9")
        
        // This assertion will fail - looking for wrong accessibility identifier
        let nonExistentField = app.textFields["SomeWrongIdentifier"]
        XCTAssertTrue(nonExistentField.waitForExistence(timeout: 2), "This test is designed to fail - wrong identifier")
    }
    
    // ✅ PASSING: Test clear and type functionality
    func testClearAndTypeInField() {
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        
        // Type initial value
        firstField.typeText("42")
        
        // Clear field (select all and delete)
        firstField.doubleTap()
        firstField.typeText("")  // Clear by typing empty string
        
        // Type new value
        firstField.typeText("7")
        
        XCTAssertEqual(firstField.value as? String ?? "", "7", "Field should contain only 7 after clear and type")
    }
    
    // ❌ FAILING: Test with nil value assertion
    func testNilValueAssertion() {
        let resultField = app.textFields.element(boundBy: 2)
        
        // The result field starts with "0", not nil
        XCTAssertNil(resultField.value, "This test is designed to fail - expecting nil but field has value")
    }
    
    // ✅ PASSING: Test multiple digit input
    func testMultipleDigitInput() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Test 123 + 456 = 579
        firstField.tap()
        firstField.typeText("123")
        
        secondField.tap()
        secondField.typeText("456")
        
        if let fieldValue = resultField.value as? String {
          XCTAssertEqual(fieldValue, "579", "123 + 456 should equal 579")
        } else {
          XCTFail("Result field value is not a string")
        }
    }
    
    // ❌ FAILING: Test with array index out of bounds
    func testArrayIndexOutOfBounds() {
        // This will fail because we're trying to access element 10 when only 3 exist
        let nonExistentField = app.textFields.element(boundBy: 10)
        XCTAssertTrue(nonExistentField.exists, "This test is designed to fail - index out of bounds")
    }
    
    // ✅ PASSING: Test default values
    func testDefaultFieldValues() {
        let firstField = app.textFields.element(boundBy: 0)
        let secondField = app.textFields.element(boundBy: 1)
        let resultField = app.textFields.element(boundBy: 2)
        
        // Check default values without any interaction
        if let firstValue = firstField.value as? String,
           let secondValue = secondField.value as? String,
           let resultValue = resultField.value as? String {
          XCTAssertEqual(firstValue, "0", "First field should default to 0")
          XCTAssertEqual(secondValue, "0", "Second field should default to 0")
          XCTAssertEqual(resultValue, "0", "Result field should default to 0")
        } else {
          XCTFail("Field values are not strings")
        }
    }
    
    // ❌ FAILING: Test with multiple assertions where second fails
    func testMultipleAssertionsWithFailure() {
        let firstField = app.textFields.element(boundBy: 0)
        
        // First assertion passes
        XCTAssertTrue(firstField.exists, "First field exists - this passes")
        
        // Second assertion fails
        if let fieldValue = firstField.value as? String {
          XCTAssertEqual(fieldValue, "100", "This test is designed to fail - expecting wrong initial value")
        } else {
          XCTFail("First field value is not a string")
        }
        
        // Third assertion (won't be reached due to failure above)
        XCTAssertNotNil(firstField.value, "Field value should not be nil")
    }
    
    // ✅ PASSING: Test app navigation elements
    func testNavigationElementsExist() {
        // Check that the app has a navigation bar or title
        let windows = app.windows
        let otherElements = app.otherElements
        
        XCTAssertGreaterThan(windows.count, 0, "App should have at least one window")
        XCTAssertGreaterThan(otherElements.count, 0, "App should have other UI elements")
        XCTAssertTrue(app.exists, "App should exist and be running")
    }
    
    // ❌ FAILING: Test with wrong type casting
    func testWrongTypeCasting() {
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        firstField.typeText("5")
        
        // This will fail because we're trying to cast to wrong type
        if let value = firstField.value as? Int {
            XCTAssertEqual(value, 5, "Value should be 5")
        } else {
            XCTFail("This test is designed to fail - value is String not Int")
        }
    }
    
    // ✅ PASSING: Test keyboard and field interaction
    func testKeyboardAppears() {
        let firstField = app.textFields.element(boundBy: 0)
        firstField.tap()
        
        // Test that we can type in the field
        firstField.typeText("123")
        XCTAssertEqual(firstField.value as? String, "123", "Field should contain typed value")
        
        // Test field exists and is accessible
        XCTAssertTrue(firstField.exists, "First field should exist")
        XCTAssertTrue(firstField.isHittable, "First field should be accessible")
    }
    
}
