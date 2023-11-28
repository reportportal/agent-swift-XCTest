//
//  StartLaunchEndPoint.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

struct StartLaunchEndPoint: EndPoint {

  let method: HTTPMethod = .post
  let relativePath: String = "launch"
  let parameters: [String : Any]

  init(launchName: String, tags: [String], mode: LaunchMode) {
    parameters = [
      "description": "",
      "mode": mode.rawValue,
      "name": launchName,
      "start_time": TimeHelper.currentTimeAsString(),
      "tags": TagHelper.defaultTags + tags
    ]
  }

}
