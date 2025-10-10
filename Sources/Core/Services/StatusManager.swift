import Foundation
import SwiftUI

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

/// Manages the app's menu bar icon status with priority-based updates and automatic timeouts
@MainActor
final class StatusManager: ObservableObject {
    /// Published property that SwiftUI can observe for menu bar icon updates
    @Published private(set) var currentIcon: String
    
    /// Current status state
    private var currentState: StatusState = .idle
    
    /// Current priority level
    private var currentPriority: StatusPriority = .app
    
    /// Active timeout task that will reset to idle state
    private var timeoutTask: Task<Void, Never>?
    
    init() {
        self.currentIcon = StatusState.idle.iconName
    }
    
    /// Updates the status icon with priority enforcement and optional timeout
    /// - Parameters:
    ///   - state: The new status state to display
    ///   - priority: The priority level of this update
    ///   - timeout: Optional timeout in seconds after which status returns to idle
    /// - Note: Only updates with equal or higher priority than current will be applied
    func updateStatus(
        state: StatusState,
        priority: StatusPriority,
        timeout: TimeInterval? = nil
    ) {
        // Priority check: only allow equal or higher priority updates
        guard priority <= currentPriority else {
            print("StatusManager: Ignoring update - priority \(priority) is lower than current \(currentPriority)")
            return
        }
        
        // Cancel any existing timeout task
        timeoutTask?.cancel()
        timeoutTask = nil
        
        // Update state and priority
        currentState = state
        currentPriority = priority
        currentIcon = state.iconName
        
        print("StatusManager: Updated to \(state) with priority \(priority)")
        
        // Set up timeout if provided
        if let timeout = timeout {
            timeoutTask = Task {
                try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                
                // Check if task was cancelled
                guard !Task.isCancelled else { return }
                
                // Return to idle state
                await returnToIdle()
            }
        }
    }
    
    /// Resets the status to idle state with app priority
    private func returnToIdle() {
        currentState = .idle
        currentPriority = .app
        currentIcon = StatusState.idle.iconName
        timeoutTask = nil
        
        print("StatusManager: Returned to idle state")
    }
    
    /// Manually resets status to idle (useful for testing or manual control)
    func resetToIdle() {
        timeoutTask?.cancel()
        returnToIdle()
    }
    
    /// Returns the current state (useful for testing)
    var state: StatusState {
        currentState
    }
    
    /// Returns the current priority (useful for testing)
    var priority: StatusPriority {
        currentPriority
    }
}
