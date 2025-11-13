//
//  TestType.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

/// ReportPortal item types for XCTest hierarchy
/// - suite: Test bundle (e.g., ExampleUITests.xctest)
/// - test: Test class (e.g., CalculatorTests)
/// - step: Individual test method (e.g., testAddition)
enum TestType: String {
  case suite = "SUITE"
  case test = "TEST"
  case step = "STEP"
}
