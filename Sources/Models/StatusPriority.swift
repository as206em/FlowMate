import Foundation

/// Represents priority levels for status updates
/// Lower raw value = higher priority
enum StatusPriority: Int, Comparable {
    case critical = 0      // Highest priority
    case proofreading = 100
    case app = 1000           // Lowest priority (default)
    
    static func < (lhs: StatusPriority, rhs: StatusPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
