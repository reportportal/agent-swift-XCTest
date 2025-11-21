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

// Response structure for log POST requests
// Server can return either:
// - Old format: {"responses":[{"id":"uuid"}]}
// - New format: {"id":"uuid"}
struct LogResponse: Decodable {
    let responses: [LogItem]?
    let id: String?
    
    struct LogItem: Decodable {
        let id: String
    }
    
    // Convenience property to get the log ID (handles both formats)
    var logId: String? {
        // Try new format first (direct id field)
        if let directId = id {
            return directId
        }
        // Fall back to old format (responses array)
        return responses?.first?.id
    }
} 
