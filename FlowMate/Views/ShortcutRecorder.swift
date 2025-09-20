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
    @FocusState private var isFocused: Bool
    
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
                        .stroke(isFocused ? Color.blue : Color.gray.opacity(0.3), lineWidth: isFocused ? 2 : 1)
                )
            
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
        .onTapGesture {
            isFocused = true
        }
        .onKeyPress { press in
            if isFocused {
                handleKeyPress(press)
                return .handled
            }
            return .ignored
        }
        .focused($isFocused)
    }
    
    private var displayText: String {
        if keyCombination.isEmpty {
            return placeholder
        }
        return keyCombination
    }
    
    private var displayColor: Color {
        if keyCombination.isEmpty {
            return .secondary
        }
        return .primary
    }
    
    private func handleKeyPress(_ press: KeyPress) {
        let key = press.key
        let modifiers = press.modifiers
        
        // Don't record if only modifier keys are pressed
        guard !isModifierKey(key) else { return }
        
        // Convert to readable string
        let keyString = convertToKeyString(key: key, modifiers: modifiers)
        keyCombination = keyString
        
        // Unfocus after recording
        isFocused = false
    }
    
    private func isModifierKey(_ key: KeyEquivalent) -> Bool {
        // Check if the key is a modifier key
        return key.character == "\u{1d}" ||  // Command
               key.character == "\u{1b}" ||  // Control
               key.character == "\u{1a}" ||  // Option/Alt
               key.character == "\u{18}"     // Shift
    }
    
    private func convertToKeyString(key: KeyEquivalent, modifiers: EventModifiers) -> String {
        var parts: [String] = []
        
        // Add modifiers in order: Cmd, Ctrl, Alt, Shift
        if modifiers.contains(.command) {
            parts.append("Cmd")
        }
        if modifiers.contains(.control) {
            parts.append("Ctrl")
        }
        if modifiers.contains(.option) {
            parts.append("Alt")
        }
        if modifiers.contains(.shift) {
            parts.append("Shift")
        }
        
        // Add the main key
        let keyString = convertKeyToString(key)
        parts.append(keyString)
        
        return parts.joined(separator: "+")
    }
    
    private func convertKeyToString(_ key: KeyEquivalent) -> String {
        switch key.character {
        case " ":
            return "Space"
        case "\t":
            return "Tab"
        case "\r":
            return "Return"
        case "\u{1b}":
            return "Escape"
        case "\u{08}":
            return "Backspace"
        case "\u{7f}":
            return "Delete"
        default:
            return key.character.uppercased()
        }
    }
    
    private func clearShortcut() {
        keyCombination = ""
        isFocused = false
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
