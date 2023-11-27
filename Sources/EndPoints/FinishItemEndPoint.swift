//
//  FinishItemEndPoint.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

struct FinishItemEndPoint: EndPoint {
  
  let method: HTTPMethod = .put
  let relativePath: String
  let parameters: [String : Any]

  init(itemID: String, status: TestStatus, launchID: String) {
    relativePath = "item/\(itemID)"
    parameters = [
      "end_time": TimeHelper.currentTimeAsString(),
      "launchUuid": launchID,
      "issue": [
        "comment": "",
        "issue_type": status == .failed ? "TO_INVESTIGATE" : "NOT_ISSUE"
      ],
      "status": status.rawValue
    ]
  }
  
}
