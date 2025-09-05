//
//  ShortcutManager.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import Foundation
import AppKit

/// Manages global keyboard shortcuts including persistence and registration
@MainActor
final class ShortcutManager: ObservableObject {
    
    // MARK: - Published Properties
    
    /// List of all configured shortcuts
    @Published private(set) var shortcuts: [Shortcut] = []
    
    // MARK: - Private Properties
    
    /// File manager for file operations
    private let fileManager = FileManager.default
    
    /// URL to the shortcuts JSON file
    private let shortcutsFileURL: URL
    
    /// JSON encoder for serialization
    private let jsonEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        return encoder
    }()
    
    /// JSON decoder for deserialization
    private let jsonDecoder = JSONDecoder()
    
    // MARK: - Initialization
    
    /// Creates a new shortcut manager and loads existing shortcuts
    init() {
        // Get Application Support directory
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!.appendingPathComponent("FlowMate", isDirectory: true)
        
        // Create directory if it doesn't exist
        try? fileManager.createDirectory(
            at: appSupportURL,
            withIntermediateDirectories: true,
            attributes: nil
        )
        
        // Set shortcuts file URL
        shortcutsFileURL = appSupportURL.appendingPathComponent("shortcuts.json")
        
        // Load existing shortcuts
        loadShortcuts()
    }
    
    // MARK: - Public Methods
    
    /// Adds a new shortcut
    /// - Parameter shortcut: The shortcut to add
    func addShortcut(_ shortcut: Shortcut) {
        shortcuts.append(shortcut)
        saveShortcuts()
    }
    
    /// Updates an existing shortcut
    /// - Parameter shortcut: The shortcut with updated values
    func updateShortcut(_ shortcut: Shortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index] = shortcut
        saveShortcuts()
    }
    
    /// Removes a shortcut
    /// - Parameter shortcut: The shortcut to remove
    func removeShortcut(_ shortcut: Shortcut) {
        shortcuts.removeAll { $0.id == shortcut.id }
        saveShortcuts()
    }
    
    /// Removes a shortcut by ID
    /// - Parameter id: The ID of the shortcut to remove
    func removeShortcut(id: UUID) {
        shortcuts.removeAll { $0.id == id }
        saveShortcuts()
    }
    
    // MARK: - Private Methods
    
    /// Loads shortcuts from the JSON file
    private func loadShortcuts() {
        guard fileManager.fileExists(atPath: shortcutsFileURL.path) else {
            // Create default shortcuts on first run
            createDefaultShortcuts()
            return
        }
        
        do {
            let data = try Data(contentsOf: shortcutsFileURL)
            shortcuts = try jsonDecoder.decode([Shortcut].self, from: data)
        } catch {
            print("Error loading shortcuts: \(error)")
            // Fallback to defaults if loading fails
            createDefaultShortcuts()
        }
    }
    
    /// Saves shortcuts to the JSON file
    private func saveShortcuts() {
        do {
            let data = try jsonEncoder.encode(shortcuts)
            try data.write(to: shortcutsFileURL)
        } catch {
            print("Error saving shortcuts: \(error)")
        }
    }
    
    /// Creates default shortcuts for first run
    private func createDefaultShortcuts() {
        let defaultShortcut = Shortcut(
            title: "Show FlowMate",
            icon: "eye",
            keyCombination: "Cmd+Shift+R",
            action: "showMainWindow"
        )
        
        shortcuts = [defaultShortcut]
        saveShortcuts()
    }
}
