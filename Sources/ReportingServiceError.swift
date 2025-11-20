//
//  ReportingServiceError.swift
//  RPAgentSwift
//
//  Created by Ruslan Popesku on 10/22/25.
//  Copyright © 2025 ReportPortal. All rights reserved.
//

import Foundation

enum ReportingServiceError: LocalizedError {
  case launchIdNotFound
  case testSuiteIdNotFound
  case configurationError
  case networkError
  case securityViolation
  
  var errorDescription: String? {
    switch self {
    case .launchIdNotFound:
      return "Launch ID not found"
    case .testSuiteIdNotFound:
      return "Test Suite ID not found"
    case .configurationError:
      return "Invalid configuration"
    case .networkError:
      return "Network error occurred"
    case .securityViolation:
      return "Security violation"
    }
  }
}
