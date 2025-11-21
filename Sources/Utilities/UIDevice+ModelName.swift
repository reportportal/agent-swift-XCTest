//  Created by Windmill Smart Solutions on 7/5/17.
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
#if os(iOS) || os(tvOS) || os(watchOS)
import UIKit

public extension UIDevice {
  
  var modelName: String {
    var model = ""
    var postfix = ""
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    var identifier = machineMirror.children.reduce("") { identifier, element in
      guard let value = element.value as? Int8, value != 0 else { return identifier }
      return identifier + String(UnicodeScalar(UInt8(value)))
    }
    if identifier == "i386" || identifier == "x86_64" {
      identifier = ProcessInfo().environment["SIMULATOR_MODEL_IDENTIFIER"] ?? "unknown"
      postfix = " (simulator)"
    }
    
    switch identifier {
    // iPod Touch
    case "iPod5,1":                                 model = "iPod Touch 5\(postfix)"
    case "iPod7,1":                                 model = "iPod Touch 6\(postfix)"
    case "iPod9,1":                                 model = "iPod Touch 7\(postfix)"
    
    // iPhone models
    case "iPhone3,1", "iPhone3,2", "iPhone3,3":     model = "iPhone 4\(postfix)"
    case "iPhone4,1":                               model = "iPhone 4s\(postfix)"
    case "iPhone5,1", "iPhone5,2":                  model = "iPhone 5\(postfix)"
    case "iPhone5,3", "iPhone5,4":                  model = "iPhone 5c\(postfix)"
    case "iPhone6,1", "iPhone6,2":                  model = "iPhone 5s\(postfix)"
    case "iPhone7,2":                               model = "iPhone 6\(postfix)"
    case "iPhone7,1":                               model = "iPhone 6 Plus\(postfix)"
    case "iPhone8,1":                               model = "iPhone 6s\(postfix)"
    case "iPhone8,2":                               model = "iPhone 6s Plus\(postfix)"
    case "iPhone8,4":                               model = "iPhone SE (1st generation)\(postfix)"
    case "iPhone9,1", "iPhone9,3":                  model = "iPhone 7\(postfix)"
    case "iPhone9,2", "iPhone9,4":                  model = "iPhone 7 Plus\(postfix)"
    case "iPhone10,1", "iPhone10,4":                model = "iPhone 8\(postfix)"
    case "iPhone10,2", "iPhone10,5":                model = "iPhone 8 Plus\(postfix)"
    case "iPhone10,3", "iPhone10,6":                model = "iPhone X\(postfix)"
    case "iPhone11,2":                              model = "iPhone XS\(postfix)"
    case "iPhone11,4", "iPhone11,6":                model = "iPhone XS Max\(postfix)"
    case "iPhone11,8":                              model = "iPhone XR\(postfix)"
    case "iPhone12,1":                              model = "iPhone 11\(postfix)"
    case "iPhone12,3":                              model = "iPhone 11 Pro\(postfix)"
    case "iPhone12,5":                              model = "iPhone 11 Pro Max\(postfix)"
    case "iPhone12,8":                              model = "iPhone SE (2nd generation)\(postfix)"
    case "iPhone13,1":                              model = "iPhone 12 mini\(postfix)"
    case "iPhone13,2":                              model = "iPhone 12\(postfix)"
    case "iPhone13,3":                              model = "iPhone 12 Pro\(postfix)"
    case "iPhone13,4":                              model = "iPhone 12 Pro Max\(postfix)"
    case "iPhone14,2":                              model = "iPhone 13 Pro\(postfix)"
    case "iPhone14,3":                              model = "iPhone 13 Pro Max\(postfix)"
    case "iPhone14,4":                              model = "iPhone 13 mini\(postfix)"
    case "iPhone14,5":                              model = "iPhone 13\(postfix)"
    case "iPhone14,6":                              model = "iPhone SE (3rd generation)\(postfix)"
    case "iPhone14,7":                              model = "iPhone 14\(postfix)"
    case "iPhone14,8":                              model = "iPhone 14 Plus\(postfix)"
    case "iPhone15,2":                              model = "iPhone 14 Pro\(postfix)"
    case "iPhone15,3":                              model = "iPhone 14 Pro Max\(postfix)"
    case "iPhone15,4":                              model = "iPhone 15\(postfix)"
    case "iPhone15,5":                              model = "iPhone 15 Plus\(postfix)"
    case "iPhone16,1":                              model = "iPhone 15 Pro\(postfix)"
    case "iPhone16,2":                              model = "iPhone 15 Pro Max\(postfix)"
    case "iPhone17,1":                              model = "iPhone 16 Pro\(postfix)"
    case "iPhone17,2":                              model = "iPhone 16 Pro Max\(postfix)"
    case "iPhone17,3":                              model = "iPhone 16\(postfix)"
    case "iPhone17,4":                              model = "iPhone 16 Plus\(postfix)"
    
    // iPad models
    case "iPad2,1", "iPad2,2", "iPad2,3", "iPad2,4":model = "iPad 2\(postfix)"
    case "iPad3,1", "iPad3,2", "iPad3,3":           model = "iPad 3\(postfix)"
    case "iPad3,4", "iPad3,5", "iPad3,6":           model = "iPad 4\(postfix)"
    case "iPad4,1", "iPad4,2", "iPad4,3":           model = "iPad Air\(postfix)"
    case "iPad5,3", "iPad5,4":                      model = "iPad Air 2\(postfix)"
    case "iPad6,11", "iPad6,12":                    model = "iPad (5th generation)\(postfix)"
    case "iPad7,5", "iPad7,6":                      model = "iPad (6th generation)\(postfix)"
    case "iPad7,11", "iPad7,12":                    model = "iPad (7th generation)\(postfix)"
    case "iPad11,6", "iPad11,7":                    model = "iPad (8th generation)\(postfix)"
    case "iPad12,1", "iPad12,2":                    model = "iPad (9th generation)\(postfix)"
    case "iPad13,18", "iPad13,19":                  model = "iPad (10th generation)\(postfix)"
    
    // iPad Air
    case "iPad11,3", "iPad11,4":                    model = "iPad Air (3rd generation)\(postfix)"
    case "iPad13,1", "iPad13,2":                    model = "iPad Air (4th generation)\(postfix)"
    case "iPad13,16", "iPad13,17":                  model = "iPad Air (5th generation)\(postfix)"
    case "iPad14,8", "iPad14,9":                    model = "iPad Air 11-inch (M2)\(postfix)"
    case "iPad14,10", "iPad14,11":                  model = "iPad Air 13-inch (M2)\(postfix)"
    
    // iPad Mini
    case "iPad2,5", "iPad2,6", "iPad2,7":           model = "iPad Mini\(postfix)"
    case "iPad4,4", "iPad4,5", "iPad4,6":           model = "iPad Mini 2\(postfix)"
    case "iPad4,7", "iPad4,8", "iPad4,9":           model = "iPad Mini 3\(postfix)"
    case "iPad5,1", "iPad5,2":                      model = "iPad Mini 4\(postfix)"
    case "iPad11,1", "iPad11,2":                    model = "iPad Mini (5th generation)\(postfix)"
    case "iPad14,1", "iPad14,2":                    model = "iPad Mini (6th generation)\(postfix)"
    
    // iPad Pro
    case "iPad6,3", "iPad6,4":                      model = "iPad Pro 9.7\"\(postfix)"
    case "iPad6,7", "iPad6,8":                      model = "iPad Pro 12.9\" (1st generation)\(postfix)"
    case "iPad7,1", "iPad7,2":                      model = "iPad Pro 12.9\" (2nd generation)\(postfix)"
    case "iPad7,3", "iPad7,4":                      model = "iPad Pro 10.5\"\(postfix)"
    case "iPad8,1", "iPad8,2", "iPad8,3", "iPad8,4": model = "iPad Pro 11\" (1st generation)\(postfix)"
    case "iPad8,5", "iPad8,6", "iPad8,7", "iPad8,8": model = "iPad Pro 12.9\" (3rd generation)\(postfix)"
    case "iPad8,9", "iPad8,10":                     model = "iPad Pro 11\" (2nd generation)\(postfix)"
    case "iPad8,11", "iPad8,12":                    model = "iPad Pro 12.9\" (4th generation)\(postfix)"
    case "iPad13,4", "iPad13,5", "iPad13,6", "iPad13,7": model = "iPad Pro 11\" (3rd generation)\(postfix)"
    case "iPad13,8", "iPad13,9", "iPad13,10", "iPad13,11": model = "iPad Pro 12.9\" (5th generation)\(postfix)"
    case "iPad14,3", "iPad14,4":                    model = "iPad Pro 11\" (4th generation)\(postfix)"
    case "iPad14,5", "iPad14,6":                    model = "iPad Pro 12.9\" (6th generation)\(postfix)"
    case "iPad16,3", "iPad16,4":                    model = "iPad Pro 11\" (M4)\(postfix)"
    case "iPad16,5", "iPad16,6":                    model = "iPad Pro 13\" (M4)\(postfix)"
    
    // Apple TV
    case "AppleTV2,1":                              model = "Apple TV 2\(postfix)"
    case "AppleTV3,1", "AppleTV3,2":                model = "Apple TV 3\(postfix)"
    case "AppleTV5,3":                              model = "Apple TV 4\(postfix)"
    case "AppleTV6,2":                              model = "Apple TV 4K\(postfix)"
    case "AppleTV11,1":                             model = "Apple TV 4K (2nd generation)\(postfix)"
    case "AppleTV14,1":                             model = "Apple TV 4K (3rd generation)\(postfix)"
    
    default:                                        model = identifier
    }
    return model
  }
  
}
#endif
