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

    /// Lets a pending task save finish before the app quits.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        let store = MainActor.assumeIsolated { TaskStore.shared }
        // Always flush: it also waits for a save that is already writing (hasUnsavedChanges is false then)
        Task { @MainActor in
            await store.flush()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        // Last chance if termination skipped the async flush above
        MainActor.assumeIsolated { TaskStore.shared.flushBlocking() }
    }
}
