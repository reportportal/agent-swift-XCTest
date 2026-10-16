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

struct FinishLaunchEndPoint: EndPoint {

  let method: HTTPMethod = .put
  let relativePath: String
  let parameters: [String : Any]

  // No status: ReportPortal derives it from the launch's items. An explicit one wins on the
  // server, so the PASSED this used to send showed failed launches as passed.
  init(launchID: String) {
    relativePath = "launch/\(launchID)/finish"
    parameters = [
      "end_time": TimeHelper.currentTimeAsString()
    ]
  }

}
