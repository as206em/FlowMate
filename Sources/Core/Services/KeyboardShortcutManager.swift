import Foundation
import AppKit

/// Protocol for keyboard shortcut handling to enable mocking in tests
protocol KeyboardShortcutManagerProtocol {
    func setupShortcut(_ shortcut: String, handler: @escaping () -> Void)
    func removeShortcut()
}

/// Service responsible for global keyboard shortcut monitoring and parsing
final class KeyboardShortcutManager: KeyboardShortcutManagerProtocol {
    private var eventMonitor: Any?
    
    deinit {
        removeShortcut()
    }
    
    /// Sets up a global keyboard shortcut with the provided handler
    /// - Parameters:
    ///   - shortcut: Shortcut string (e.g., "command+.", "ctrl+shift+p")
    ///   - handler: Closure to execute when shortcut is triggered
    func setupShortcut(_ shortcut: String, handler: @escaping () -> Void) {
        // Remove existing monitor if any
        removeShortcut()
        
        // Parse shortcut string
        let (keyCode, modifiers) = parseShortcut(shortcut)
        
        // Set up new global event monitor
        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == keyCode && event.modifierFlags.intersection(.deviceIndependentFlagsMask) == modifiers {
                handler()
            }
        }
        
        Task { @MainActor in
            Logger.shared.debug("KeyboardShortcutManager: Set up shortcut '\(shortcut)'")
        }
    }
    
    /// Removes the current keyboard shortcut monitor
    func removeShortcut() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
            Task { @MainActor in
                Logger.shared.debug("KeyboardShortcutManager: Removed shortcut")
            }
        }
    }
    
    /// Parses a shortcut string into key code and modifier flags
    /// - Parameter shortcut: Shortcut string (e.g., "command+.", "ctrl+shift+p")
    /// - Returns: Tuple of (keyCode, modifierFlags)
    private func parseShortcut(_ shortcut: String) -> (UInt16, NSEvent.ModifierFlags) {
        var keyCode: UInt16 = 0
        var modifiers: NSEvent.ModifierFlags = []
        
        let components = shortcut.lowercased().components(separatedBy: "+")
        
        for component in components {
            switch component.trimmingCharacters(in: .whitespaces) {
            // Modifier keys
            case "command", "cmd":
                modifiers.insert(.command)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "option", "opt":
                modifiers.insert(.option)
            case "shift":
                modifiers.insert(.shift)
            
            // Special characters
            case "/":
                keyCode = 44
            case ".":
                keyCode = 47
            case ",":
                keyCode = 43
            case ";":
                keyCode = 41
            case "'":
                keyCode = 39
            case "[":
                keyCode = 33
            case "]":
                keyCode = 30
            case "\\":
                keyCode = 42
            case "`":
                keyCode = 50
            case "=":
                keyCode = 24
            case "-":
                keyCode = 27
            
            // Letter keys (a-z)
            case "a": keyCode = 0
            case "b": keyCode = 11
            case "c": keyCode = 8
            case "d": keyCode = 2
            case "e": keyCode = 14
            case "f": keyCode = 3
            case "g": keyCode = 5
            case "h": keyCode = 4
            case "i": keyCode = 34
            case "j": keyCode = 38
            case "k": keyCode = 40
            case "l": keyCode = 37
            case "m": keyCode = 46
            case "n": keyCode = 45
            case "o": keyCode = 31
            case "p": keyCode = 35
            case "q": keyCode = 12
            case "r": keyCode = 15
            case "s": keyCode = 1
            case "t": keyCode = 17
            case "u": keyCode = 32
            case "v": keyCode = 9
            case "w": keyCode = 13
            case "x": keyCode = 7
            case "y": keyCode = 16
            case "z": keyCode = 6
            
            // Number keys (0-9)
            case "0": keyCode = 29
            case "1": keyCode = 18
            case "2": keyCode = 19
            case "3": keyCode = 20
            case "4": keyCode = 21
            case "5": keyCode = 23
            case "6": keyCode = 22
            case "7": keyCode = 26
            case "8": keyCode = 28
            case "9": keyCode = 25
            
            // Function keys
            case "f1": keyCode = 122
            case "f2": keyCode = 120
            case "f3": keyCode = 99
            case "f4": keyCode = 118
            case "f5": keyCode = 96
            case "f6": keyCode = 97
            case "f7": keyCode = 98
            case "f8": keyCode = 100
            case "f9": keyCode = 101
            case "f10": keyCode = 109
            case "f11": keyCode = 103
            case "f12": keyCode = 111
            
            // Special keys
            case "space": keyCode = 49
            case "return", "enter": keyCode = 36
            case "tab": keyCode = 48
            case "escape", "esc": keyCode = 53
            case "delete": keyCode = 51
            case "up": keyCode = 126
            case "down": keyCode = 125
            case "left": keyCode = 123
            case "right": keyCode = 124
            
            default:
                break
            }
        }
        
        return (keyCode, modifiers)
    }
}
