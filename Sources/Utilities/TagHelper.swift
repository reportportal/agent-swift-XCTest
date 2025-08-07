//
//  TagHelper.swift
//  RPAgentSwiftXCTest
//
//  Created by Stas Kirichok on 23-08-2018.
//  Copyright © 2018 Windmill Smart Solutions. All rights reserved.
//

import Foundation
#if canImport(UIKit)
import UIKit
#endif

enum TagHelper {
  
  static let defaultTags: [String] = {
    #if canImport(UIKit)
    return [
      DeviceHelper.detectedOSName(),
      UIDevice.current.systemVersion,
      UIDevice.current.modelName,
      UIDevice.current.model
    ]
    #else
    // Fallback for platforms without UIKit (defensive programming)
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    return [
      "macOS",
      osVersion,
      "Mac",
      "Desktop"
    ]
    #endif
  }()
  
}
