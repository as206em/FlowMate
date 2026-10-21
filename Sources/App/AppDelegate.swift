import AppKit
import ApplicationServices

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Set activation policy for menu bar app to allow windows to receive focus
        NSApp.setActivationPolicy(.accessory)

        // The shortcut and copy/paste need Accessibility access; ask once at launch if it's missing
        if !AXIsProcessTrusted() {
            let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
    }
}
