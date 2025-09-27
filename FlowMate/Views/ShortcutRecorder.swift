//
//  ShortcutRecorder.swift
//  FlowMate
//
//  Created by Asem MKL on 2025/09/05.
//

import SwiftUI
import AppKit

/// A custom input field that captures keystrokes and converts them to readable key strings
struct ShortcutRecorder: View {
    
    @Binding var keyCombination: String
    @State private var isRecording = false
    @FocusState private var isFocused: Bool
    @State private var eventMonitor: Any?
    
    private let placeholder = "Click to record shortcut"
    
    var body: some View {
        HStack {
            Text(displayText)
                .foregroundColor(displayColor)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.gray.opacity(0.2))
                .cornerRadius(6)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(isRecording ? Color.blue : Color.gray.opacity(0.3), lineWidth: isRecording ? 2 : 1)
                )
                .onTapGesture {
                    startRecording()
                }
            
            if !keyCombination.isEmpty {
                Button(action: clearShortcut) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
                .opacity(0.7)
                .onHover { hovering in
                    if hovering {
                        NSCursor.pointingHand.push()
                    } else {
                        NSCursor.pop()
                    }
                }
            }
        }
        .onAppear {
            setupKeyEventMonitor()
        }
        .onChange(of: isRecording) { _, newValue in
            if newValue {
                startEventMonitoring()
            } else {
                stopEventMonitoring()
            }
        }
    }
    
    private var displayText: String {
        if keyCombination.isEmpty {
            return isRecording ? "Press keys..." : placeholder
        }
        return keyCombination
    }
    
    private var displayColor: Color {
        if keyCombination.isEmpty {
            return isRecording ? .primary : .secondary
        }
        return .primary
    }
    
    private func startRecording() {
        isRecording = true
        isFocused = true
    }
    
    private func stopRecording() {
        isRecording = false
        isFocused = false
    }
    
    private func setupKeyEventMonitor() {
        // Setup is handled by the onChange modifier
    }
    
    private func startEventMonitoring() {
        // Create a local monitor to capture key events
        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            if self.isRecording {
                self.handleKeyEvent(event)
                return nil // Consume the event
            }
            return event // Pass through if not recording
        }
    }
    
    private func stopEventMonitoring() {
        if let monitor = eventMonitor {
            NSEvent.removeMonitor(monitor)
            eventMonitor = nil
        }
    }
    
    private func handleKeyEvent(_ event: NSEvent) {
        // Don't record if only modifier keys are pressed
        let keyCode = event.keyCode
        let modifierFlags = event.modifierFlags
        
        // Check if this is a modifier-only event by checking if it's a modifier key code
        let modifierKeyCodes: Set<UInt16> = [55, 56, 58, 59, 60, 61, 62, 63] // Cmd, Shift, Alt, Ctrl, etc.
        
        let isModifierOnly = modifierKeyCodes.contains(keyCode) && modifierFlags.contains(.deviceIndependentFlagsMask)
        
        if isModifierOnly {
            // If it's just a modifier key, don't record it
            return
        }
        
        // Convert to readable string
        let keyString = convertNSEventToKeyString(event: event)
        
        // Only record if we have a valid key combination
        if !keyString.isEmpty {
            DispatchQueue.main.async {
                self.keyCombination = keyString
                self.stopRecording()
            }
        }
    }
    
    private func convertNSEventToKeyString(event: NSEvent) -> String {
        var parts: [String] = []
        
        let modifierFlags = event.modifierFlags
        
        // Add modifiers in order: Cmd, Ctrl, Alt, Shift
        if modifierFlags.contains(.command) {
            parts.append("Cmd")
        }
        if modifierFlags.contains(.control) {
            parts.append("Ctrl")
        }
        if modifierFlags.contains(.option) {
            parts.append("Alt")
        }
        if modifierFlags.contains(.shift) {
            parts.append("Shift")
        }
        
        // Get the key character or special key name
        let keyString = getKeyName(from: event)
        
        // Only add key if we have modifiers or it's a special key
        if !keyString.isEmpty {
            parts.append(keyString)
            return parts.joined(separator: "+")
        }
        
        return ""
    }
    
    private func getKeyName(from event: NSEvent) -> String {
        let keyCode = event.keyCode
        
        // Special key mappings based on macOS key codes
        let specialKeys: [UInt16: String] = [
            0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X",
            8: "C", 9: "V", 11: "B", 12: "Q", 13: "W", 14: "E", 15: "R",
            16: "Y", 17: "T", 18: "1", 19: "2", 20: "3", 21: "4", 22: "6",
            23: "5", 24: "=", 25: "9", 26: "7", 27: "-", 28: "8", 29: "0",
            30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 36: "Return",
            37: "L", 38: "J", 39: "'", 40: "K", 41: ";", 42: "\\", 43: ",",
            44: "/", 45: "N", 46: "M", 47: ".", 48: "Tab", 49: "Space",
            50: "`", 51: "Backspace", 52: "Enter", 53: "Escape", 54: "RCommand",
            55: "LCommand", 56: "LShift", 57: "CapsLock", 58: "LAlt", 59: "LControl",
            60: "RShift", 61: "RAlt", 62: "RControl", 63: "Fn", 64: "F17",
            65: "KeypadPeriod", 67: "KeypadAsterisk", 69: "KeypadPlus", 71: "KeypadClear",
            72: "VolumeUp", 73: "VolumeDown", 74: "Mute", 75: "KeypadDivide",
            76: "KeypadEnter", 78: "KeypadMinus", 79: "F18", 80: "F19", 81: "KeypadEquals",
            82: "Keypad0", 83: "Keypad1", 84: "Keypad2", 85: "Keypad3", 86: "Keypad4",
            87: "Keypad5", 88: "Keypad6", 89: "Keypad7", 90: "F20", 91: "Keypad8",
            92: "Keypad9", 96: "F5", 97: "F6", 98: "F7", 99: "F3", 100: "F8",
            101: "F9", 103: "F1", 105: "F13", 106: "F16", 107: "F14", 109: "F10",
            111: "F12", 113: "F15", 114: "Help", 115: "Home", 116: "PageUp",
            117: "Delete", 118: "F4", 119: "End", 120: "F2", 121: "PageDown",
            122: "F1", 123: "Left", 124: "Right", 125: "Down", 126: "Up"
        ]
        
        if let specialKey = specialKeys[keyCode] {
            return specialKey
        }
        
        // For regular characters, use the event's characters
        if let characters = event.charactersIgnoringModifiers {
            if characters.count == 1 {
                let char = characters.uppercased()
                // Handle special cases
                switch char {
                case "\r": return "Return"
                case "\n": return "Return"
                case "\t": return "Tab"
                case " ": return "Space"
                case "\u{1b}": return "Escape"
                case "\u{08}": return "Backspace"
                case "\u{7f}": return "Delete"
                default: return char
                }
            }
        }
        
        return ""
    }
    
    private func clearShortcut() {
        keyCombination = ""
    }
}

struct ShortcutRecorder_Previews: PreviewProvider {
    @State static private var testCombination = "Cmd+Shift+A"
    
    static var previews: some View {
        VStack(spacing: 20) {
            ShortcutRecorder(keyCombination: $testCombination)
            Text("Recorded: \(testCombination)")
        }
        .padding()
    }
}
