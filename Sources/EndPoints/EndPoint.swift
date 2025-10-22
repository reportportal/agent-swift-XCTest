//
//  EndPoint.swift
//  RPAgentSwift
//
//  Created by Windmill Smart Solutions on 8/29/17.
//  Copyright © 2017 Oxagile. All rights reserved.
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
