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

final class AuthorizationPlugin: HTTPClientPlugin {

  private let token: String
  
  init(token: String) {
    self.token = token
  }
  
  func processRequest(_ originRequest: inout URLRequest) {
    // Set Authorization header
    originRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    
    // Only set Content-Type if it's not already present (to preserve multipart headers)
    if originRequest.value(forHTTPHeaderField: "Content-Type") == nil {
      originRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    }
  }
  
}

extension Dictionary {
  public static func +=(lhs: inout [Key: Value], rhs: [Key: Value]) { rhs.forEach({ lhs[$0] = $1}) }
}
