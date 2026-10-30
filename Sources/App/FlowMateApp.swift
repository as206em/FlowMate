import SwiftUI
import AppKit


@main
struct FlowMateApp: App {
    @StateObject private var statusManager = StatusManager()
    @StateObject private var appState: AppState
    /// Task manager data; loads from disk on first use and saves on quit (see AppDelegate)
    @StateObject private var taskStore = TaskStore.shared
    /// Observed here (not only inside the label view) so the menu bar clock redraws every second:
    /// MenuBarExtra labels don't reliably refresh views that observe objects of their own.
    @StateObject private var ticker = TaskStore.shared.ticker
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
        MenuBarExtra {
            StatusMenuView()
                .environmentObject(appState)
                .environmentObject(statusManager)
                .environmentObject(taskStore)
        } label: {
            // The status icon, plus how many timers run when any do (or the running clock, if chosen)
            let running = taskStore.workspace.runningTimers.count
            Image(systemName: statusManager.currentIcon)
            if running > 0 {
                if taskStore.preferences.showsMenuBarClock {
                    Text(MenuBarClockText.title(store: taskStore, now: ticker.now))
                        .monospacedDigit()
                } else {
                    Text("\(running)")
                }
            }
        }
        .menuBarExtraStyle(.window)
    }
}
