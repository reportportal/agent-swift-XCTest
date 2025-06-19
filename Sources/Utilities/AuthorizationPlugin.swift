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
    print("🔒 AuthPlugin: Headers BEFORE processing: \(originRequest.allHTTPHeaderFields ?? [:])")
    if originRequest.allHTTPHeaderFields == nil {
      originRequest.allHTTPHeaderFields = [:]
    }
    // Preserve existing "Content-Type" set by the request builder (e.g. multipart)
    if originRequest.value(forHTTPHeaderField: "Content-Type") == nil {
      print("🔒 AuthPlugin: Content-Type is missing, setting to 'application/json'.")
      originRequest.setValue("application/json", forHTTPHeaderField: "Content-Type")
    } else {
        print("🔒 AuthPlugin: Content-Type already present ('\(originRequest.value(forHTTPHeaderField: "Content-Type") ?? "N/A")'), not overriding.")
    }
    // Always set / override the Authorization header
    originRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    print("🔒 AuthPlugin: Headers AFTER processing: \(originRequest.allHTTPHeaderFields ?? [:])")
  }
  
}

extension Dictionary {
  public static func +=(lhs: inout [Key: Value], rhs: [Key: Value]) { rhs.forEach({ lhs[$0] = $1}) }
}

