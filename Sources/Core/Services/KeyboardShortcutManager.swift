import Foundation
import AppKit

/// Protocol for keyboard shortcut handling to enable mocking in tests
protocol KeyboardShortcutManagerProtocol {
    /// Returns false when the shortcut string is invalid; the previous shortcut stays active.
    @discardableResult
    func setupShortcut(_ shortcut: String, handler: @escaping () -> Void) -> Bool
    func removeShortcut()
}

/// Service responsible for global keyboard shortcut monitoring and parsing
final class KeyboardShortcutManager: KeyboardShortcutManagerProtocol {
    private var eventMonitor: Any?

    /// Only these modifiers are compared, so Caps Lock, Fn and the numeric-pad flag don't break matching.
    private static let relevantModifiers: NSEvent.ModifierFlags = [.command, .control, .option, .shift]

    deinit {
        removeShortcut()
    }

    /// Sets up a global keyboard shortcut with the provided handler
    /// - Parameters:
    ///   - shortcut: Shortcut string (e.g., "command+.", "ctrl+shift+p")
    ///   - handler: Closure to execute when shortcut is triggered
    /// - Returns: false if the shortcut can't be parsed. The existing shortcut is left in place.
    @discardableResult
    func setupShortcut(_ shortcut: String, handler: @escaping () -> Void) -> Bool {
        guard let (keyCode, modifiers) = Self.parseShortcut(shortcut) else {
            Task { @MainActor in
                Logger.shared.error("KeyboardShortcutManager: Invalid shortcut '\(shortcut)' - keeping previous shortcut")
            }
            return false
        }

        removeShortcut()

        eventMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
            let pressed = event.modifierFlags.intersection(Self.relevantModifiers)
            if event.keyCode == keyCode && pressed == modifiers {
                handler()
            }
        }

        Task { @MainActor in
            Logger.shared.debug("KeyboardShortcutManager: Set up shortcut '\(shortcut)'")
        }
        return true
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

    /// Builds a shortcut string like "command+shift+p" from a pressed key, or nil for keys
    /// that can't be used (a lone modifier, or a key FlowMate doesn't know).
    static func shortcutString(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> String? {
        let specialKeys: [UInt16: String] = [
            49: "space", 36: "return", 48: "tab", 53: "escape", 51: "delete",
            123: "left", 124: "right", 125: "down", 126: "up",
            122: "f1", 120: "f2", 99: "f3", 118: "f4", 96: "f5", 97: "f6",
            98: "f7", 100: "f8", 101: "f9", 109: "f10", 103: "f11", 111: "f12"
        ]
        // Match the physical key, so Shift (which changes "." into ">") doesn't matter
        let typingKeys = "abcdefghijklmnopqrstuvwxyz0123456789".map(String.init) + ["/", ".", ",", ";", "'", "[", "]", "\\", "`", "=", "-"]
        let key: String
        if let special = specialKeys[keyCode] {
            key = special
        } else if let name = typingKeys.first(where: { parseShortcut("command+\($0)")?.0 == keyCode }) {
            key = name
        } else {
            return nil
        }

        var parts: [String] = []
        if modifiers.contains(.control) { parts.append("control") }
        if modifiers.contains(.option) { parts.append("option") }
        if modifiers.contains(.shift) { parts.append("shift") }
        if modifiers.contains(.command) { parts.append("command") }
        parts.append(key)

        let shortcut = parts.joined(separator: "+")
        return isValidShortcut(shortcut) ? shortcut : nil
    }

    /// Turns "command+shift+p" into "⇧⌘P" for display in menus.
    static func displayString(for shortcut: String) -> String {
        var modifiers = ""
        var key = ""
        for raw in shortcut.lowercased().components(separatedBy: "+") {
            let part = raw.trimmingCharacters(in: .whitespaces)
            switch part {
            case "control", "ctrl": modifiers += "⌃"
            case "option", "opt", "alt": modifiers += "⌥"
            case "shift": modifiers += "⇧"
            case "command", "cmd": modifiers += "⌘"
            case "period": key = "."
            case "comma": key = ","
            case "slash": key = "/"
            case "space": key = "Space"
            case "return", "enter": key = "↩"
            case "tab": key = "⇥"
            case "escape", "esc": key = "⎋"
            case "delete": key = "⌫"
            case "up": key = "↑"
            case "down": key = "↓"
            case "left": key = "←"
            case "right": key = "→"
            default: key = part.uppercased()
            }
        }
        // Apple's standard modifier order is ⌃⌥⇧⌘
        let order: [Character] = ["⌃", "⌥", "⇧", "⌘"]
        let sorted = String(order.filter { modifiers.contains($0) })
        return sorted + key
    }

    /// Returns true if the shortcut string can be used as a global shortcut.
    static func isValidShortcut(_ shortcut: String) -> Bool {
        parseShortcut(shortcut) != nil
    }

    /// Parses a shortcut string into key code and modifier flags
    /// - Parameter shortcut: Shortcut string (e.g., "command+.", "ctrl+shift+p")
    /// - Returns: Tuple of (keyCode, modifierFlags), or nil if the string has no key, an unknown part,
    ///   or is a plain typing key without a modifier (which would fire on normal typing).
    static func parseShortcut(_ shortcut: String) -> (UInt16, NSEvent.ModifierFlags)? {
        var keyCode: UInt16?
        var modifiers: NSEvent.ModifierFlags = []

        let components = shortcut.lowercased().components(separatedBy: "+")

        for component in components {
            let part = component.trimmingCharacters(in: .whitespaces)
            // A key part must appear once, and only as the last part.
            if keyCode != nil { return nil }
            switch part {
            // Modifier keys
            case "command", "cmd":
                modifiers.insert(.command)
            case "control", "ctrl":
                modifiers.insert(.control)
            case "option", "opt", "alt":
                modifiers.insert(.option)
            case "shift":
                modifiers.insert(.shift)
            
            // Special characters
            case "/", "slash":
                keyCode = 44
            case ".", "period":
                keyCode = 47
            case ",", "comma":
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
                return nil
            }
        }

        guard let keyCode else { return nil }

        // Without a modifier, only function keys are allowed; anything else would trigger while typing.
        let functionKeyCodes: Set<UInt16> = [122, 120, 99, 118, 96, 97, 98, 100, 101, 109, 103, 111]
        if modifiers.isEmpty && !functionKeyCodes.contains(keyCode) {
            return nil
        }

        return (keyCode, modifiers)
    }
}
