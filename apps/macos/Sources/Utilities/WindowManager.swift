import SwiftUI
import AppKit

@MainActor
final class WindowManager: NSObject {
    static let shared = WindowManager()
    
    private var windows: [String: NSWindow] = [:]
    
    private override init() {
        super.init()
    }
    
    /// Shows (or brings forward) a light-only Focus window.
    /// `fullSizeContent` hides the title and lets the content run under a transparent titlebar (sidebar windows).
    func showWindow<Content: View>(
        id: String,
        title: String,
        content: @escaping () -> Content,
        size: NSSize,
        fullSizeContent: Bool = false
    ) {
        if let existingWindow = windows[id] {
            // Activate too, or the window shows but keystrokes keep going to the other app
            NSApp.activate(ignoringOtherApps: true)
            existingWindow.makeKeyAndOrderFront(nil)
            return
        }
        
        var style: NSWindow.StyleMask = [.titled, .closable, .miniaturizable, .resizable]
        if fullSizeContent { style.insert(.fullSizeContentView) }
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: style,
            backing: .buffered,
            defer: false
        )

        window.title = title
        window.appearance = NSAppearance(named: .aqua)
        window.backgroundColor = NSColor(hex: 0xFBFBFA) // Focus.canvas
        if fullSizeContent {
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
        }
        window.contentView = NSHostingView(rootView: content())
        window.center()
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.level = .floating
        
        windows[id] = window
        window.makeKeyAndOrderFront(nil)
        window.makeMain()
        NSApp.activate(ignoringOtherApps: true)
        window.orderFrontRegardless()
    }
    
    /// True if the window with this id is the one receiving keyboard input
    func isKeyWindow(id: String) -> Bool {
        guard let window = windows[id] else { return false }
        return window.isKeyWindow
    }

    func closeWindow(id: String) {
        windows[id]?.close()
        windows.removeValue(forKey: id)
    }
}

extension WindowManager: NSWindowDelegate {
    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        
        // Remove the window from our tracking
        for (id, trackedWindow) in windows where trackedWindow === window {
            windows.removeValue(forKey: id)
            break
        }
    }
}