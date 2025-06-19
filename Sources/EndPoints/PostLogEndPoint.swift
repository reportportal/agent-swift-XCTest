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
    
    if !attachments.isEmpty {
      print("🔍 PostLogEndPoint: Taking multipart branch - trying compatible field names")
      
      // The server explicitly requires a part named 'json_request_part' containing the log metadata.
      let logEntry: [String: Any] = [
        "item_id": itemUuid,
        "launch_id": launchUuid,
        "time": TimeHelper.currentTimeAsString(),
        "message": message,
        "level": level
      ]
      
      // The server expects an ARRAY of log entries for the 'json_request_part'
      parameters = [
        "json_request_part": [logEntry]
      ]
    } else {
      print("🔍 PostLogEndPoint: Taking simple JSON branch - flat structure")
      // For simple JSON requests, use flat structure with original field names
      parameters = [
        "item_id": itemUuid,
        "level": level,
        "message": message,
        "time": TimeHelper.currentTimeAsString()  // Use string format for simple requests
      ]
    }
    
    self.attachments = attachments
    print("🔍 PostLogEndPoint: Final parameters keys: \(parameters.keys)")
  }

}
