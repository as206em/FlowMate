import Foundation
import AppKit

/// Protocol for clipboard operations to enable mocking in tests
protocol ClipboardServiceProtocol {
    func getSelectedText() -> String?
    func copyToClipboard(_ text: String)
    func pasteFromClipboard()
}

/// Service responsible for clipboard operations
final class ClipboardService: ClipboardServiceProtocol {
    
    /// Retrieves currently selected text by simulating Command+C.
    /// Returns nil when nothing is selected (the copy doesn't change the clipboard),
    /// so old clipboard contents are never mistaken for a selection.
    /// Restores the previous clipboard contents afterwards.
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        let changeCountBefore = pasteboard.changeCount

        // Use Command+C to copy instead of Command+X to cut
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 0x08 = 'C' key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)

        // Wait up to 500ms for the frontmost app to write to the clipboard
        let deadline = Date().addingTimeInterval(0.5)
        while pasteboard.changeCount == changeCountBefore && Date() < deadline {
            usleep(20_000) // 20ms
        }

        // Clipboard didn't change: nothing was selected (or the app doesn't support copy)
        guard pasteboard.changeCount != changeCountBefore else {
            return nil
        }

        let selectedText = pasteboard.string(forType: .string)

        // Put back what the user had on the clipboard before
        if let previousContents = previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previousContents, forType: .string)
        }

        guard let selectedText, !selectedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return nil
        }
        return selectedText
    }

    /// Copies the provided text to the clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    
    /// Pastes content from clipboard by simulating Command+V
    func pasteFromClipboard() {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // 0x09 = 'V' key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
    }
}
