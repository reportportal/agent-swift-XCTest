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
    if !attachments.isEmpty {
      // Create the log entry structure exactly as Java client does
      let logEntry: [String: Any] = [
        "item_id": itemUuid,
        "launch_id": launchUuid,
        "time": TimeHelper.currentTimeAsString(),
        "message": message,
        "level": level
      ]
      
      // CRITICAL: Java client sends json_request_part as an ARRAY of log entries
      // This matches the server's expectation for multipart log requests
      parameters = [
        "json_request_part": [logEntry]  // Array containing single log entry
      ]
    } else {
      // For simple JSON requests, use flat structure
      parameters = [
        "item_id": itemUuid,
        "level": level,
        "message": message,
        "time": TimeHelper.currentTimeAsString()
      ]
    }
    
    self.attachments = attachments
  }

}
