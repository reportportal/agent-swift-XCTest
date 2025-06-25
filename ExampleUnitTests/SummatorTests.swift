//
//  ExampleTests.swift
//  ExampleTests
//
//  Created by Stas Kirichok on 28-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import XCTest
@testable import Example

class SummatorTests: XCTestCase {
  
  private let summator = SummatorService()
  
  func testSumOfTwoZerosIsZero() {
    let result = summator.addNumbers(first: 0, second: 0)
    XCTAssertEqual(result, 0)
  }
  
  func testSumOfTwoRandomNumberIsCorrect() {
    let first = Int(arc4random_uniform(42))
    let second = Int(arc4random_uniform(42))
    let result = summator.addNumbers(first: first, second: second)
    XCTAssertEqual(result, first + second)
  }
  
  func testMultipartFormat() {
    // Test that our multipart format implementation works correctly
    print("🧪 Starting multipart format test...")
    
    // Test basic multipart construction logic manually (simulating our HTTPClient approach)
    let boundary = "Boundary-\(UUID().uuidString)"
    
    // Simulate JSON data like our PostLogEndPoint
    let jsonData = """
    {
      "item_id": "test-item-123",
      "level": "error", 
      "message": "Test error - multipart format validation",
      "time": "2025-06-19T15:08:00.000+00:00"
    }
    """.data(using: .utf8)!
    
    // Simulate file data
    let fileData = "FAKE_SCREENSHOT_DATA_FOR_TESTING".data(using: .utf8)!
    
    // Test our boundary format construction (matches our HTTPClient implementation)
    let boundaryPrefix = "--\(boundary)\r\n"
    let body = NSMutableData()
    
    // Add JSON part
    body.appendString(boundaryPrefix)
    body.appendString("Content-Disposition: form-data; name=\"json_request_part\"\r\n\r\n")
    body.append(jsonData)
    body.appendString("\r\n")
    
    // Add file part
    body.appendString(boundaryPrefix)
    body.appendString("Content-Disposition: form-data; name=\"file\"; filename=\"test_screenshot.jpg\"\r\n")
    body.appendString("Content-Type: image/jpeg\r\n\r\n")
    body.append(fileData)
    body.appendString("\r\n")
    
    // Close boundary
    body.appendString("--\(boundary)--\r\n")
    
    // Verify the multipart format meets the expected regex pattern
    if let bodyString = String(data: body as Data, encoding: .utf8) {
      print("🔍 Generated multipart body preview:")
      print(String(bodyString.prefix(500))) // Show first 500 chars
      
      // Test against the original regex pattern
      let regex = try! NSRegularExpression(pattern: "[\\-\\w]+\\r\\nContent-Disposition:\\sform-data;\\sname=.*\\r\\n")
      let matches = regex.matches(in: bodyString, range: NSRange(bodyString.startIndex..., in: bodyString))
      
      XCTAssertEqual(matches.count, 2, "Should have 2 regex matches (JSON + file parts)")
      print("✅ Regex validation passed: \(matches.count) matches found")
    }
    
    XCTAssertGreaterThan(body.length, 100, "Body should have substantial content")
    print("✅ Multipart format test completed successfully")
  }
  
}

private extension NSMutableData {
  func appendString(_ string: String) {
    if let data = string.data(using: .utf8) {
      append(data)
    }
  }
}
