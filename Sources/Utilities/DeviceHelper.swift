//  Created by Ruslan Popesku on 08/01/2025.
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
#if canImport(UIKit)
import UIKit
#endif

enum DeviceHelper {
    
    /// Detects the actual OS name, handling iPadOS detection for iPads running iOS 13+
    static func detectedOSName() -> String {
        #if canImport(UIKit)
        var osName = UIDevice.current.systemName
        if osName == "iOS" && UIDevice.current.userInterfaceIdiom == .pad {
            // iPad running iOS 13+ reports as "iOS" but is actually iPadOS
            let osVersionComponents = UIDevice.current.systemVersion.split(separator: ".")
            if let majorVersion = osVersionComponents.first, let major = Int(majorVersion), major >= 13 {
                osName = "iPadOS"
            }
        }
        return osName
        #else
        return "Unknown"
        #endif
    }
    
    /// Returns the OS name and version as a formatted string
    static func osNameAndVersion() -> String {
        #if canImport(UIKit)
        return "\(detectedOSName()) \(UIDevice.current.systemVersion)"
        #else
        return "Unknown"
        #endif
    }
}
