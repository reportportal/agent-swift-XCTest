//
//  StartLaunchEndPoint.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2025 ReportPortal. All rights reserved.
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
