//  Created by Ruslan Popesku on 10/22/25.
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
