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