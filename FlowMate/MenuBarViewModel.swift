//
//  MenuBarViewModel.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import SwiftUI

@MainActor
final class MenuBarViewModel: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isMenuBarVisible = true
    
    // MARK: - Private Properties
    private var statusItem: NSStatusItem?
    
    // MARK: - Initialization
    init() {
        setupMenuBar()
    }
    
    // MARK: - Public Methods
    func showMenuBar() {
        guard statusItem == nil else { return }
        setupMenuBar()
        isMenuBarVisible = true
    }
    
    func hideMenuBar() {
        guard let statusItem = statusItem else { return }
        NSStatusBar.system.removeStatusItem(statusItem)
        self.statusItem = nil
        isMenuBarVisible = false
    }
    
    // MARK: - Private Methods
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem?.button {
            // Set the custom icon
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true // Makes it work with dark/light mode
                button.image = icon
            } else {
                // Fallback to system icon
                button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "FlowMate")
            }
            button.action = #selector(menuBarButtonClicked)
            button.target = self
        }
        
        // Create menu
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Open FlowMate", action: #selector(openApp), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit FlowMate", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem?.menu = menu
    }
    
    @objc private func menuBarButtonClicked() {
        // Handle button click - show the main app window
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func openApp() {
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApp.terminate(self)
    }
    
    deinit {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
