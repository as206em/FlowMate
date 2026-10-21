import AppKit

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app to allow windows to receive focus
        NSApp.setActivationPolicy(.accessory)

        // The shortcut and copy/paste need Accessibility access; ask once at launch if it's missing
        Task { @MainActor in
            AppState.promptForAccessibilityAccess()
        }
    }
}
