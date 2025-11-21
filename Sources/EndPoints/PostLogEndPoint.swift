//  Created by Stas Kirichok on 23-08-2018.
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
        "itemUuid": itemUuid,        // V2 API uses camelCase (accepts item_id as alias)
        "launchUuid": launchUuid,    // V2 API uses camelCase (NO alias for launch_id!)
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
      // V2 API requires both itemUuid and launchUuid for all log requests
      // CRITICAL: Parameter names MUST be camelCase (launchUuid, not launch_id)
      parameters = [
        "itemUuid": itemUuid,       // Accepts item_id as alias
        "launchUuid": launchUuid,   // NO alias - must use exact name!
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
