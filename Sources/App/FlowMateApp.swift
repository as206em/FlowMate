import SwiftUI
import AppKit


@main
struct FlowMateApp: App {
    @StateObject private var statusManager = StatusManager()
    @StateObject private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Create StatusManager first
        let statusManager = StatusManager()
        _statusManager = StateObject(wrappedValue: statusManager)
        
        // Create AppState with StatusManager dependency
        _appState = StateObject(wrappedValue: AppState(
            configurationManager: nil,
            statusManager: statusManager
        ))
    }
    
    var body: some Scene {
        MenuBarExtra("FlowMate", systemImage: statusManager.currentIcon) {
            StatusMenuView()
                .environmentObject(appState)
                .environmentObject(statusManager)
        }
        .menuBarExtraStyle(.menu)
    }
}
