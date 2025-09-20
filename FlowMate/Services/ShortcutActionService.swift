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
        case "showMainWindow":
            showMainWindow()
        case "toggleRecording":
            toggleRecording()
        case "pauseRecording":
            pauseRecording()
        case "stopRecording":
            stopRecording()
        case "showSettings":
            showSettings()
        default:
            print("Unknown action: \(actionId)")
        }
    }
    
    /// Shows the main FlowMate window
    private func showMainWindow() {
        // TODO: Implement showing main window
        print("Showing main FlowMate window")
        NotificationCenter.default.post(name: .showMainWindow, object: nil)
    }
    
    /// Toggles recording state
    private func toggleRecording() {
        // TODO: Implement toggle recording
        print("Toggling recording")
        NotificationCenter.default.post(name: .toggleRecording, object: nil)
    }
    
    /// Pauses recording
    private func pauseRecording() {
        // TODO: Implement pause recording
        print("Pausing recording")
        NotificationCenter.default.post(name: .pauseRecording, object: nil)
    }
    
    /// Stops recording
    private func stopRecording() {
        // TODO: Implement stop recording
        print("Stopping recording")
        NotificationCenter.default.post(name: .stopRecording, object: nil)
    }
    
    /// Shows settings window
    private func showSettings() {
        // TODO: Implement show settings
        print("Showing settings")
        NotificationCenter.default.post(name: .showSettings, object: nil)
    }
}

// MARK: - Notification Names
extension Notification.Name {
    static let showMainWindow = Notification.Name("showMainWindow")
    static let toggleRecording = Notification.Name("toggleRecording")
    static let pauseRecording = Notification.Name("pauseRecording")
    static let stopRecording = Notification.Name("stopRecording")
    static let showSettings = Notification.Name("showSettings")
}
