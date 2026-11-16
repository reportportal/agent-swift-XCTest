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

struct StartItemEndPoint: EndPoint {

  let method: HTTPMethod = .post
  var relativePath: String
  let parameters: [String : Any]

  /// - Parameters:
  ///   - uuid: Client-chosen item uuid; lets every process of a shared launch address the same item.
  ///   - codeRef: Stable identity (`Module.Class[.method]`), also sent as `testCaseId`, so
  ///     ReportPortal tracks the item's history across launches.
  ///   - retry: Ask ReportPortal to nest an earlier attempt of the same item under this one.
  init(itemName: String, parentID: String? = nil, launchID: String, type: TestType, attributes: [[String: String]] = [],
       uuid: String? = nil, codeRef: String? = nil, retry: Bool = false) {
    relativePath = "item"
    if let parentID = parentID {
      relativePath += "/\(parentID)"
    }

    // V2 API uses camelCase parameter names (launchUuid not launch_id)
    // No legacy "tags" field: server-side it's a @JsonAlias of "attributes" (last field in
    // the JSON wins), so an empty "tags": [] could wipe the item's attributes whenever the
    // random dictionary serialization order put it after "attributes".
    var parameters: [String: Any] = [
      "description": "",
      "launchUuid": launchID,  // V2 API: camelCase
      "name": itemName,
      "start_time": TimeHelper.currentTimeAsString(),
      "type": type.rawValue,
      "attributes": attributes
    ]
    // Assigning nil leaves the key out.
    parameters["uuid"] = uuid
    parameters["codeRef"] = codeRef
    parameters["testCaseId"] = codeRef
    if retry {
      parameters["retry"] = true
    }
    self.parameters = parameters
  }

}
