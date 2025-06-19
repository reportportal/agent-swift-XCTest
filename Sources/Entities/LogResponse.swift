import Foundation

// Response structure for log POST requests
// Server returns: {"responses":[{"id":"uuid"}]}
struct LogResponse: Decodable {
    let responses: [LogItem]
    
    struct LogItem: Decodable {
        let id: String
    }
    
    // Convenience property to get the first log ID
    var logId: String? {
        return responses.first?.id
    }
} 