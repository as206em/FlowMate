import Foundation
import AppKit

/// Protocol for clipboard operations to enable mocking in tests
protocol ClipboardServiceProtocol {
    func getSelectedText() -> String?
    func copyToClipboard(_ text: String)
}

/// Service responsible for clipboard operations
final class ClipboardService: ClipboardServiceProtocol {
    
    /// Retrieves currently selected text by simulating Command+C
    /// Preserves previous clipboard contents if different from selection
    func getSelectedText() -> String? {
        let pasteboard = NSPasteboard.general
        let previousContents = pasteboard.string(forType: .string)
        
        // Use Command+C to copy instead of Command+X to cut
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true) // 0x08 = 'C' key
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cgAnnotatedSessionEventTap)
        keyUp?.post(tap: .cgAnnotatedSessionEventTap)
        
        usleep(100000) // 100ms delay to allow clipboard to update
        
        let selectedText = pasteboard.string(forType: .string)
        
        // Restore previous clipboard contents only if we actually copied something different
        if let previousContents = previousContents, selectedText != previousContents {
            pasteboard.clearContents()
            pasteboard.setString(previousContents, forType: .string)
        }
        
        return selectedText
    }
    
    /// Copies the provided text to the clipboard
    func copyToClipboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
