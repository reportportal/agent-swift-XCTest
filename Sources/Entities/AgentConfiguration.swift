//
//  AgentConfiguration.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

struct AgentConfiguration {
  
  let reportPortalURL: URL
  let projectName: String
  let launchName: String
  let shouldSendReport: Bool
  let portalToken: String
  let tags: [String]
  let launchMode: LaunchMode
  let testNameRules: NameRules
  
}
