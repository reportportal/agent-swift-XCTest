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

/// V2 Launch Start endpoint with mandatory UUID for idempotent launch creation
/// 
/// ## V2 API Behavior:
/// - **Idempotent**: Multiple calls with same UUID return same launch
/// - **409 Conflict**: Returns existing launch data (not an error!)
/// - **Parallel-safe**: All workers can call simultaneously with same UUID
///
/// ## UUID Strategy:
/// - **CI/CD Mode**: All workers use `RP_LAUNCH_UUID` environment variable
/// - **Local Mode**: Each worker generates unique UUID (separate launches)
struct StartLaunchEndPoint: EndPoint {

  let method: HTTPMethod = .post
  let relativePath: String = "launch"  // Base URL is already /api/v2/{project}
  let parameters: [String : Any]

  /// Create V2 launch start endpoint with mandatory UUID
  /// - Parameters:
  ///   - launchName: Launch name (may include test plan name)
  ///   - tags: Tags for categorization
  ///   - mode: Launch mode (DEFAULT or DEBUG)
  ///   - attributes: Custom metadata (device info, OS version, etc.)
  ///   - uuid: **REQUIRED** Launch UUID for idempotent creation
  init(launchName: String, tags: [String], mode: LaunchMode, attributes: [[String: String]] = [], uuid: String) {
    let params: [String: Any] = [
      "description": "",
      "mode": mode.rawValue,
      "name": launchName,
      "start_time": TimeHelper.currentTimeAsString(),
      "tags": TagHelper.defaultTags + tags,
      "attributes": attributes,
      "uuid": uuid  // REQUIRED in V2 API
    ]
    
    parameters = params
  }

}
