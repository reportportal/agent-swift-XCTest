//
//  PostLogEndPoint.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018. All rights reserved.
//

import Foundation

struct PostLogEndPoint: EndPoint {

  let method: HTTPMethod = .post
  let relativePath: String = "log"
  let parameters: [String : Any]
  let attachments: [FileAttachment]
  
  var encoding: ParameterEncoding {
    return attachments.isEmpty ? .json : .multipartFormData
  }

  // Original initializer for simple text logs (no attachments)
  init(itemID: String, level: String, message: String) {
    parameters = [
      "item_id": itemID,
      "level": level,
      "message": message,
      "time": TimeHelper.currentTimeAsString()
    ]
    attachments = []
  }
  
  // Enhanced initializer for logs with attachments (follows ReportPortal multipart spec)
  init(itemUuid: String, launchUuid: String, level: String, message: String, attachments: [FileAttachment] = []) {
    print("🔍 PostLogEndPoint: Initializing with attachments count: \(attachments.count)")
    
    // Create the JSON request part according to OFFICIAL ReportPortal API spec from GitHub issues
    // Based on issue #866: https://github.com/reportportal/reportportal/issues/866
    var logEntry = [
      "itemUuid": itemUuid,      // Official ReportPortal uses itemUuid (not item_id)
      "launchUuid": launchUuid,  // Official ReportPortal uses launchUuid (not launch_id) 
      "time": TimeHelper.currentTimeAsMilliseconds(),  // Official uses numeric milliseconds (not ISO string)
      "message": message,
      "level": level  // Keep original case
    ] as [String : Any]
    
    if !attachments.isEmpty {
      print("🔍 PostLogEndPoint: Taking multipart branch - wrapping in json_request_part")
      
      // Add file reference to JSON as per official spec
      if let firstAttachment = attachments.first {
        logEntry["file"] = ["name": firstAttachment.filename]
      }
      
      // For multipart requests, JSON goes in json_request_part field as ARRAY (not single object)
      parameters = [
        "json_request_part": [logEntry]  // Official ReportPortal expects array format!
      ]
    } else {
      print("🔍 PostLogEndPoint: Taking simple JSON branch - flat structure")
      // For simple JSON requests, use flat structure
      parameters = logEntry
    }
    
    self.attachments = attachments
    print("🔍 PostLogEndPoint: Final parameters keys: \(parameters.keys)")
  }

}
