//
//  MenuBarManager.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/04.
//

import SwiftUI
import AppKit

@MainActor
class MenuBarManager: NSObject, ObservableObject {
    static let shared = MenuBarManager()
    
    private var statusItem: NSStatusItem?
    private var mainWindow: NSWindow?
    
    private override init() {
        super.init()
    }
    
    func setupMenuBar() {
        // Create status item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem?.button {
            // Set the icon - using system icon for now, can be replaced with custom image
            button.image = NSImage(systemSymbolName: "keyboard", accessibilityDescription: "FlowMate")
            button.action = #selector(toggleMainWindow)
            button.target = self
        }
        
        // Create main window
        createMainWindow()
    }
    
    private func createMainWindow() {
        let contentView = SettingsContentView()
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        
        window.contentView = NSHostingView(rootView: contentView)
        window.title = "FlowMate"
        window.isReleasedWhenClosed = false // Keep window alive when closed
        window.center()
        
        mainWindow = window
    }
    
    @objc private func toggleMainWindow() {
        if let window = mainWindow {
            if window.isVisible {
                window.orderOut(nil)
                NSApp.hide(nil)
            } else {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
            }
        } else {
            createMainWindow()
            mainWindow?.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    
    func showMainWindow() {
        if mainWindow == nil {
            createMainWindow()
        }
        mainWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    func hideMainWindow() {
        mainWindow?.orderOut(nil)
        NSApp.hide(nil)
    }
}
