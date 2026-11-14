import SwiftUI
import AppKit


@main
struct FlowMateApp: App {
    @StateObject private var statusManager: StatusManager
    @StateObject private var appState: AppState
    /// Task manager data; loads from disk on first use and saves on quit (see AppDelegate)
    @StateObject private var taskStore = TaskStore.shared
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        let statusManager = StatusManager()
        let appState = AppState(configurationManager: nil, statusManager: statusManager)
        _statusManager = StateObject(wrappedValue: statusManager)
        _appState = StateObject(wrappedValue: appState)
        // The menu bar icon and its panel are AppKit's (see MenuBarController); they go in once
        // the app has finished launching
        DispatchQueue.main.async {
            MenuBarController.shared.install(appState: appState, statusManager: statusManager, store: .shared)
        }
    }

    var body: some Scene {
        // SwiftUI needs a scene; this one is never shown. The menu bar icon and panel are
        // MenuBarController's: MenuBarExtra's window left its old outline on screen after shrinking.
        MenuBarExtra("FlowMate", systemImage: "checkmark.circle", isInserted: .constant(false)) {
            EmptyView()
        }
    }
}
