//
//  GetCurrentLaunchEndPoint.swift
//  Alamofire
//
//  Created by Stas Kirichok on 27-08-2018.
//

import Foundation

struct GetCurrentLaunchEndPoint: EndPoint {

  let encoding: ParameterEncoding = .url
  let relativePath: String = "launch/latest"
  let parameters: [String : Any]

  init() {
    parameters = [
      "page.sort": "startTime"
    ]
  }

}
