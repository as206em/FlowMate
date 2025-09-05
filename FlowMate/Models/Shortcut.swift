//
//  Shortcut.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import Foundation

/// Represents a global keyboard shortcut that can be triggered system-wide
struct Shortcut: Identifiable, Codable {
    
    /// Unique identifier for the shortcut
    let id: UUID
    
    /// User-friendly name for the shortcut
    var title: String
    
    /// SF Symbol name or custom icon identifier
    var icon: String
    
    /// String representation of the key combination (e.g., "Cmd+Shift+R")
    var keyCombination: String
    
    /// Identifier for the action to execute when the shortcut is triggered
    var action: String
    
    /// Creates a new shortcut
    /// - Parameters:
    ///   - id: Unique identifier (defaults to new UUID)
    ///   - title: User-friendly name
    ///   - icon: SF Symbol name or icon identifier
    ///   - keyCombination: Key combination string
    ///   - action: Action identifier
    init(
        id: UUID = UUID(),
        title: String,
        icon: String,
        keyCombination: String,
        action: String
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.keyCombination = keyCombination
        self.action = action
    }
}
