import Foundation
import AppKit

/// Protocol for key monitoring to enable mocking in tests
protocol KeyMonitorServiceProtocol {
    func setupEscapeKeyMonitor(dismissAction: @escaping () -> Void) -> Any?
    func removeKeyMonitor(_ monitor: Any?)
}

/// Service responsible for monitoring keyboard events, particularly ESC key for dismissing dialogs
final class KeyMonitorService: KeyMonitorServiceProtocol {
    
    /// Sets up a local keyboard monitor for ESC key events
    /// - Parameter dismissAction: Closure to execute when ESC key is pressed
    /// - Returns: Monitor object that can be used to remove the monitor
    func setupEscapeKeyMonitor(dismissAction: @escaping () -> Void) -> Any? {
        return NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // ESC key
                dismissAction()
                return nil // Consume the event
            }
            return event
        }
    }
    
    /// Removes a previously set up keyboard monitor
    /// - Parameter monitor: The monitor object returned by setupEscapeKeyMonitor
    func removeKeyMonitor(_ monitor: Any?) {
        if let monitor = monitor {
            NSEvent.removeMonitor(monitor)
        }
    }
}
