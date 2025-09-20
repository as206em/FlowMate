//
//  ShortcutActionService.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import Foundation

/// Service that handles executing shortcut actions
class ShortcutActionService {
    
    /// Shared instance
    static let shared = ShortcutActionService()
    
    /// Private initializer to enforce singleton pattern
    private init() {}
    
    /// Executes the action associated with a shortcut
    /// - Parameter actionId: The ID of the action to execute
    func executeAction(for actionId: String) {
        switch actionId {
        case "generalProofreading":
            generalProofreading()
        default:
            print("Unknown action: \(actionId)")
        }
    }
    
    /// Performs general proofreading action
    private func generalProofreading() {
        // TODO: Implement general proofreading functionality
        print("Performing general proofreading")
        NotificationCenter.default.post(name: .generalProofreading, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let generalProofreading = Notification.Name("generalProofreading")
}
