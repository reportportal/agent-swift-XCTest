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

/// Launch creation response
/// V1 API: {"id": "uuid", "number": 123}
/// V2 API: {"id": "uuid"} (number is optional)
struct FirstLaunch: Decodable  {
    let id: String
    let number: Int?  // Optional - V2 API doesn't return this
}

struct Launch: Decodable  {
    let owner: String?
    let share: Bool?
    let id: Int
    let uuid, name: String?
    let number: Int?
    let startTime, endTime, lastModified: String?
    let status: String?
    let statistics: Statistics?
    let attributes: [Attributes?]?
    let mode: String?
    let analysing: [String]?
    let approximateDuration: Float?
    let hasRetries, rerun: Bool?
    let metadata: Metadata?
    let description: String?
}

struct Metadata: Decodable {
    let rpClusterLastRun: String?
}

struct Statistics: Decodable {
    let defects: [String: [String: Int32]]?
    let executions: [String: Int32]?
}

struct LaunchList: Decodable {
    let uuid: String
    let number: Int
    let status: String?
}

struct LaunchListInfo: Decodable {
  let content: [Launch]
  let page: Page?
}

struct Attributes: Decodable {
    let key: String?
    let value: String?
}

struct Page: Decodable {
    let number: Int
    let size: Int
    let totalElements: Int
    let totalPages: Int
}

struct LaunchID: Decodable {
    let id: String
    let number: Int
}
