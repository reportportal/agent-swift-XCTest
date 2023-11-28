//
//  FinishLaunchEndPoint.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

struct FinishLaunchEndPoint: EndPoint {

  let method: HTTPMethod = .put
  let relativePath: String
  let parameters: [String : Any]

  init(launchID: String, status: TestStatus) {
    relativePath = "launch/\(launchID)/finish"
    parameters = [
      "status": status.rawValue,
      "end_time": TimeHelper.currentTimeAsString()
    ]
  }

}
