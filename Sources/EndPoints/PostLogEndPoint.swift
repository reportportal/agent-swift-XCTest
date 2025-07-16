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
      var logEntry: [String: Any] = [
        "itemUuid": itemUuid,      // EXACT field name from working Java example
        "launchUuid": launchUuid,  // EXACT field name from working Java example
        "time": TimeHelper.currentTimeAsString(),
        "message": message,
        "level": level
      ]
      
      // Add file reference if attachment exists (matches working example)
      if let firstAttachment = attachments.first {
        logEntry["file"] = [
          "name": firstAttachment.filename  // matches: "file":{"name":"ee390d92-9794-4a7f-b288-66cb5c7d3269"}
        ]
      }
      
      // CRITICAL: Java client sends json_request_part as an ARRAY of log entries
      // This matches the server's expectation for multipart log requests
      parameters = [
        "json_request_part": [logEntry]  // Array containing single log entry
      ]
    } else {
      // For simple JSON requests, use flat structure
      parameters = [
        "itemUuid": itemUuid,      // Use consistent field names
        "launchUuid": launchUuid,  // Use consistent field names
        "level": level,
        "message": message,
        "time": TimeHelper.currentTimeAsString()
      ]
    }
    
    // Map attachments to use binary_part field name (matches working Java example)
    self.attachments = attachments.map { attachment in
      FileAttachment(
        data: attachment.data,
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        fieldName: "binary_part"  // EXACT field name from working example
      )
    }
  }

}
