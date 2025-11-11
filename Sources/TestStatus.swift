//
//  TestStatus.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

enum TestStatus: String {
  case passed = "PASSED"
  case failed = "FAILED"
  case stopped = "STOPPED"
  case skipped = "SKIPPED"
  case reseted = "RESETED"
  case cancelled = "CANCELLED"
}
