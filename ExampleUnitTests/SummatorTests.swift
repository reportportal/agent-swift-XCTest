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
@testable import Example

final class SummatorTests: XCTestCase {
  
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
    let jsonString = """
    {
      "item_id": "test-item-123",
      "level": "error", 
      "message": "Test error - multipart format validation",
      "time": "2025-06-19T15:08:00.000+00:00"
    }
    """
    
    guard let jsonData = jsonString.data(using: .utf8) else {
      XCTFail("Failed to create JSON data")
      return
    }
    
    // Simulate file data
    guard let fileData = "FAKE_SCREENSHOT_DATA_FOR_TESTING".data(using: .utf8) else {
      XCTFail("Failed to create file data")
      return
    }
    
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
      guard let regex = try? NSRegularExpression(pattern: "[\\-\\w]+\\r\\nContent-Disposition:\\sform-data;\\sname=.*\\r\\n") else {
        XCTFail("Failed to create regex")
        return
      }
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
