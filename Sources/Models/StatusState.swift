import Foundation

/// Represents the current state of the app status icon
enum StatusState {
    case idle
    case processing
    case success
    case failure
    
    /// Maps each state to its corresponding SF Symbol icon name
    var iconName: String {
        switch self {
        case .idle:
            return "checkmark.circle"
        case .processing:
            return "arrow.triangle.2.circlepath"
        case .success:
            return "hand.thumbsup.fill"
        case .failure:
            return "exclamationmark.triangle.fill"
        }
    }
}
