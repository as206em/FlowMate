import AppKit
import SwiftUI

/// The main FlowMate window (sidebar, board, list, sprints, milestones).
/// A normal resizable window; the app shows a Dock icon while it's open.
@MainActor
enum TasksWindow {
    static let identifier = NSUserInterfaceItemIdentifier("tasks")

    /// Shared so the scope, tab and open task survive closing the window.
    static let viewModel = TasksViewModel(defaults: .standard)

    private static var window: NSWindow?
    private static var keyMonitor: TasksKeyMonitor?
    private static let delegate = WindowDelegate()

    /// Shows the window (creating it on first use) and brings the app forward.
    /// Pass `openTask` to open that task's side panel, e.g. from the menu bar.
    static func show(store: TaskStore? = nil, openTask taskId: UUID? = nil) {
        let store = store ?? .shared
        let window = window ?? makeWindow(store: store)
        self.window = window
        if let taskId, store.task(taskId) != nil {
            viewModel.openTask(taskId)
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    static var isVisible: Bool { window?.isVisible ?? false }

    private static func makeWindow(store: TaskStore) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1280, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.identifier = identifier
        window.title = AppChannel.current.displayName
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(hex: 0xFBFBFA)
        window.minSize = NSSize(width: 980, height: 640)
        window.isReleasedWhenClosed = false
        window.level = .normal
        window.delegate = delegate

        let root = TasksRootView()
            .environmentObject(store)
            .environmentObject(viewModel)
        let hosting = NSHostingView(rootView: root)
        hosting.sizingOptions = []
        window.contentView = hosting

        keyMonitor = TasksKeyMonitor(window: window, model: viewModel, store: store)

        window.center()
        window.setFrameAutosaveName("FlowMateTasksWindow")
        return window
    }

    private final class WindowDelegate: NSObject, NSWindowDelegate {
        func windowWillClose(_ notification: Notification) {
            // Back to a menu bar only app once the main window is gone
            MainActor.assumeIsolated {
                TasksWindow.viewModel.dropTarget = nil
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
