//
//  PredefinedShortcuts.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import Foundation

/// Represents a predefined shortcut with its associated function
struct PredefinedShortcut {
    /// Unique identifier for the shortcut
    let id: String
    
    /// User-friendly name for the shortcut
    let title: String
    
    /// SF Symbol name for the icon
    let icon: String
    
    /// Default key combination
    let defaultKeyCombination: String
    
    /// Creates a new predefined shortcut
    /// - Parameters:
    ///   - id: Unique identifier
    ///   - title: User-friendly name
    ///   - icon: SF Symbol name
    ///   - defaultKeyCombination: Default key combination
    init(
        id: String,
        title: String,
        icon: String,
        defaultKeyCombination: String
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.defaultKeyCombination = defaultKeyCombination
    }
}

/// Service that manages predefined shortcuts
class PredefinedShortcutsService {
    
    /// Shared instance
    static let shared = PredefinedShortcutsService()
    
    /// All predefined shortcuts
    private(set) var shortcuts: [PredefinedShortcut] = []
    
    /// Private initializer to enforce singleton pattern
    private init() {
        setupPredefinedShortcuts()
    }
    
    /// Sets up all predefined shortcuts
    private func setupPredefinedShortcuts() {
        shortcuts = [
            PredefinedShortcut(
                id: "showMainWindow",
                title: "Show FlowMate",
                icon: "eye",
                defaultKeyCombination: "Cmd+Shift+R"
            ),
            
            PredefinedShortcut(
                id: "toggleRecording",
                title: "Toggle Recording",
                icon: "record.circle",
                defaultKeyCombination: "Cmd+Shift+T"
            ),
            
            PredefinedShortcut(
                id: "pauseRecording",
                title: "Pause Recording",
                icon: "pause.circle",
                defaultKeyCombination: "Cmd+Shift+P"
            ),
            
            PredefinedShortcut(
                id: "stopRecording",
                title: "Stop Recording",
                icon: "stop.circle",
                defaultKeyCombination: "Cmd+Shift+S"
            ),
            
            PredefinedShortcut(
                id: "showSettings",
                title: "Show Settings",
                icon: "gear",
                defaultKeyCombination: "Cmd+Shift+,"
            )
        ]
    }
    
    /// Gets a predefined shortcut by ID
    /// - Parameter id: The shortcut ID
    /// - Returns: The predefined shortcut, or nil if not found
    func getShortcut(by id: String) -> PredefinedShortcut? {
        return shortcuts.first { $0.id == id }
    }
    
    /// Gets the default key combination for a shortcut
    /// - Parameter id: The shortcut ID
    /// - Returns: The default key combination, or empty string if not found
    func getDefaultKeyCombination(for id: String) -> String {
        return getShortcut(by: id)?.defaultKeyCombination ?? ""
    }
}
