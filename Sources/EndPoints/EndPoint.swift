//  Created by Windmill Smart Solutions on 8/29/17.
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

enum ParameterEncoding {
  case url
  case json
  case multipartFormData
}

enum HTTPMethod: String {
  case get = "GET"
  case post = "POST"
  case put = "PUT"
  case delete = "DELETE"
}

// Structure for file attachments
struct FileAttachment {
  let data: Data
  let filename: String
  let mimeType: String
  let fieldName: String
  
  init(data: Data, filename: String, mimeType: String = "image/png", fieldName: String = "file") {
    self.data = data
    self.filename = filename
    self.mimeType = mimeType
    self.fieldName = fieldName
  }
}

protocol EndPoint {

  var headers: [String: String] { get }
  var encoding: ParameterEncoding { get }
  var method: HTTPMethod { get }
  var relativePath: String { get }
  var parameters: [String: Any] { get }
  var attachments: [FileAttachment] { get }

}

extension EndPoint {

  var headers: [String: String] { return [:] }
  var encoding: ParameterEncoding { return .json }
  var parameters: [String: Any] { return [:] }
  var attachments: [FileAttachment] { return [] }

}
