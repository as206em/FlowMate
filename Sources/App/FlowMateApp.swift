import SwiftUI
import AppKit

@available(macOS 13.0, *)
@main
struct FlowMateApp: App {
    @StateObject private var appState = AppState(configurationManager: nil)
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        MenuBarExtra("FlowMate", systemImage: appState.statusIcon) {
            StatusMenuView()
                .environmentObject(appState)
        }
        .menuBarExtraStyle(.menu)
    }
}
