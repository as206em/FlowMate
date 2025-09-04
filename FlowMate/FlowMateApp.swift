//
//  FlowMateApp.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/08/27.
//

import SwiftUI

@main
struct FlowMateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        // Remove the WindowGroup since we're using a menu bar app
        Settings {
            EmptyView()
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hide the dock icon and menu bar app
        NSApp.setActivationPolicy(.accessory)
        
        // Setup the menu bar
        MenuBarManager.shared.setupMenuBar()
        
        // Hide the main window initially
        MenuBarManager.shared.hideMainWindow()
    }
    
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // When app is reopened (e.g., clicked in dock or via Cmd+Tab), show the main window
        MenuBarManager.shared.showMainWindow()
        return false
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Don't terminate the app when the last window is closed
        return false
    }
}
