//
//  EndPointBuilder.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

class AuthorizationPlugin: HTTPClientPlugin {

  private let token: String
  private lazy var defaultHeader: [String: String] = {
    return [
      "Content-Type": "application/json",
      "Authorization": "Bearer \(token)",
    ]
  }()
  
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

