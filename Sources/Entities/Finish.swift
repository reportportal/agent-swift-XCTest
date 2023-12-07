//
//  Finish.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation

enum FinishKeys: String, CodingKey {
  case msg = "message"
}


struct Finish: Decodable {
  let message: String
}

struct LaunchFinish: Decodable {
    let id: String
    let link: String
    let number: Int
}
