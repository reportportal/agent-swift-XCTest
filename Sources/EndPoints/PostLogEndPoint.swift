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
      var logEntry: [String: Any] = [
        "item_id": itemUuid,
        "launch_id": launchUuid,
        "time": TimeHelper.currentTimeAsString(),
        "message": message,
        "level": level
      ]
      
      if let firstAttachment = attachments.first {
        logEntry["file"] = [
          "name": firstAttachment.filename
        ]
      }
      
      parameters = [
        "json_request_part": [logEntry]
      ]
    } else {
      // V2 API requires both item_id and launch_id for all log requests
      parameters = [
        "item_id": itemUuid,
        "launch_id": launchUuid,
        "level": level,
        "message": message,
        "time": TimeHelper.currentTimeAsString()
      ]
    }
    
    self.attachments = attachments.map { attachment in
      FileAttachment(
        data: attachment.data,
        filename: attachment.filename,
        mimeType: attachment.mimeType,
        fieldName: "binary_part"
      )
    }
  }

}
