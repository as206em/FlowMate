//
//  MenuBarViewModel.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import SwiftUI
import AppKit

@MainActor
final class MenuBarViewModel: NSObject, ObservableObject, NSWindowDelegate {

    // MARK: - Published
    @Published var isMenuBarVisible = true

    // MARK: - Private
    private var statusItem: NSStatusItem?
    private var windowController: NSWindowController?

    // MARK: - Init
    override init() {
        super.init()
        setupMenuBar()
        
        // Show main window on startup
        DispatchQueue.main.async {
            self.showMainWindow()
        }
    }

    // MARK: - Public
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

    // MARK: - Menu Bar
    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            if let icon = NSImage(named: "MenuBarIcon") {
                icon.isTemplate = true
                button.image = icon
            } else {
                button.image = NSImage(systemSymbolName: "brain", accessibilityDescription: "FlowMate")
            }
            // Leave action nil so the menu appears on click.
            button.action = nil
            button.target = nil
        }

        let menu = NSMenu()

        // Open
        let openItem = NSMenuItem(
            title: "Open FlowMate",
            action: #selector(openApp(_:)),
            keyEquivalent: "o"
        )
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        // Quit (system terminate:)
        let quitItem = NSMenuItem(
            title: "Quit FlowMate",
            action: #selector(quitApp(_:)),
            keyEquivalent: "q"
        )
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem?.menu = menu
    }

    // MARK: - Actions
    @objc private func openApp(_ sender: Any?) {
        NSApp.activate(ignoringOtherApps: true)
        showMainWindow()
    }
    
    @objc private func quitApp(_ sender: Any?) {
        // Clean up window controller
        windowController?.close()
        windowController = nil
        
        // Remove menu bar item
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
        
        // Quit the application
        NSApp.terminate(nil)
    }

    // MARK: - Window Management
    private func showMainWindow() {
        // Create once, reuse later.
        if windowController == nil || windowController?.window == nil {
            let rootView = SettingsContentView() // Use SettingsContentView as the main view
            let hosting = NSHostingController(rootView: rootView)

            let window = NSWindow(contentViewController: hosting)
            window.title = "FlowMate"
            window.setContentSize(NSSize(width: 900, height: 620))
            window.styleMask = [.titled, .closable, .resizable, .miniaturizable]
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("FlowMateMainWindow")
            window.center()
            
            // Set window delegate to track close events
            window.delegate = self

            let controller = NSWindowController(window: window)
            self.windowController = controller
        }

        // Show dock icon when window opens
        NSApp.setActivationPolicy(.regular)
        
        windowController?.showWindow(nil)
        windowController?.window?.makeKeyAndOrderFront(nil)
    }
    
    // MARK: - NSWindowDelegate
    func windowWillClose(_ notification: Notification) {
        // Hide dock icon when window closes
        NSApp.setActivationPolicy(.accessory)
        
        // Clean up window controller reference
        if let window = notification.object as? NSWindow,
           windowController?.window === window {
            windowController = nil
        }
    }

    deinit {
        if let statusItem = statusItem {
            NSStatusBar.system.removeStatusItem(statusItem)
        }
    }
}
