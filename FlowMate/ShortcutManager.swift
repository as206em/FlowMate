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
    
    /// Updates an existing shortcut's key combination
    /// - Parameter shortcut: The shortcut with updated key combination
    func updateShortcutKeyCombination(_ shortcut: Shortcut) {
        guard let index = shortcuts.firstIndex(where: { $0.id == shortcut.id }) else { return }
        shortcuts[index] = shortcut
        saveShortcuts()
    }
    
    /// Gets the predefined shortcut service
    private var predefinedShortcutsService: PredefinedShortcutsService {
        return PredefinedShortcutsService.shared
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
            let savedShortcuts = try jsonDecoder.decode([Shortcut].self, from: data)
            
            // Merge with predefined shortcuts to ensure all predefined shortcuts exist
            mergeWithPredefinedShortcuts(savedShortcuts: savedShortcuts)
        } catch {
            print("Error loading shortcuts: \(error)")
            // Fallback to defaults if loading fails
            createDefaultShortcuts()
        }
    }
    
    /// Merges saved shortcuts with predefined shortcuts
    /// - Parameter savedShortcuts: The shortcuts loaded from file
    private func mergeWithPredefinedShortcuts(savedShortcuts: [Shortcut]) {
        var mergedShortcuts: [Shortcut] = []
        
        // Add all predefined shortcuts, using saved key combinations if they exist
        for predefined in predefinedShortcutsService.shortcuts {
            if let saved = savedShortcuts.first(where: { $0.id == predefined.id }) {
                // Use saved key combination if it exists
                mergedShortcuts.append(Shortcut(
                    id: predefined.id,
                    title: predefined.title,
                    icon: predefined.icon,
                    keyCombination: saved.keyCombination,
                    action: predefined.id
                ))
            } else {
                // Use default key combination
                mergedShortcuts.append(Shortcut(
                    id: predefined.id,
                    title: predefined.title,
                    icon: predefined.icon,
                    keyCombination: predefined.defaultKeyCombination,
                    action: predefined.id
                ))
            }
        }
        
        shortcuts = mergedShortcuts
        saveShortcuts() // Save the merged result
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
        var defaultShortcuts: [Shortcut] = []
        
        for predefined in predefinedShortcutsService.shortcuts {
            defaultShortcuts.append(Shortcut(
                id: predefined.id,
                title: predefined.title,
                icon: predefined.icon,
                keyCombination: predefined.defaultKeyCombination,
                action: predefined.id
            ))
        }
        
        shortcuts = defaultShortcuts
        saveShortcuts()
    }
}
