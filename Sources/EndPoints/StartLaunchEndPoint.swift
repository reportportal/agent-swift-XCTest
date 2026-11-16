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
/// - **Idempotent**: Multiple calls with same UUID report into the same launch (reporting is
///   asynchronous: a duplicate start gets a success response and is dropped server-side)
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
    // Do NOT add a legacy "tags" field here. Server-side, StartRQ declares
    // @JsonAlias({"attributes","tags"}) — "tags" and "attributes" deserialize into the SAME
    // property, and Jackson keeps whichever appears LAST in the JSON document. Swift
    // dictionaries serialize in per-process random key order, so sending both made every
    // shard a coin flip: when "tags" landed after "attributes", the keyless tag strings
    // REPLACED all keyed attributes (merge_group, device, os, …) — the intermittent
    // "launch lost all attributes / N of 6 didn't merge" bug. Tags already reach
    // ReportPortal as keyed {"key":"tag"} attributes inside `attributes`.
    let params: [String: Any] = [
      "description": "",
      "mode": mode.rawValue,
      "name": launchName,
      "start_time": TimeHelper.currentTimeAsString(),
      "attributes": attributes,
      "uuid": uuid  // REQUIRED in V2 API
    ]

    parameters = params
  }

}
