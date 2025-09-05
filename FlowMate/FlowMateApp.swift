//
//  FlowMateApp.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/08/27.
//

import SwiftUI

@main
struct FlowMateApp: App {
    @NSApplicationDelegateAdaptor private var appDelegate: AppDelegate
    @StateObject private var menuBarViewModel = MenuBarViewModel()
    
    var body: some Scene {
        // Menu bar-only app - no automatic window creation
        Settings {
            EmptyView()
        }
        .commands {
            // Remove default app commands that don't apply to menu bar apps
            CommandGroup(replacing: .newItem, addition: { })
            CommandGroup(replacing: .appInfo, addition: { })
            CommandGroup(replacing: .appVisibility, addition: { })
            CommandGroup(replacing: .systemServices, addition: { })
        }
    }
}

// App delegate to handle application lifecycle
class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // Return false to keep app running in background
        return false
    }
    
    func applicationWillFinishLaunching(_ notification: Notification) {
        // Set activation policy to accessory (no dock icon) before app finishes launching
        NSApp.setActivationPolicy(.accessory)
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // App is already configured in MenuBarViewModel
    }
}
