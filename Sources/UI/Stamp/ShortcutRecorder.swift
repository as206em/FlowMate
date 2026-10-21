import SwiftUI
import AppKit

/// Shows a shortcut as key caps, with a button to record a new one by pressing it.
struct ShortcutRecorder: View {
    @Binding var shortcut: String

    /// True while any recorder is waiting for keys, so Esc doesn't also close the window
    static var isRecording = false

    @State private var recording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                if recording {
                    Text("Press the new shortcut…")
                        .font(Stamp.body)
                        .foregroundColor(Stamp.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 44)
                        .stampSurface(fill: Stamp.sun, shadow: .sm)
                } else {
                    ForEach(Array(keyCaps.enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(Stamp.display(18))
                            .foregroundColor(Stamp.ink)
                            .frame(minWidth: 44, minHeight: 44)
                            .padding(.horizontal, cap.count > 1 ? 8 : 0)
                            .stampSurface(fill: Stamp.paperRaised, shadow: .md)
                    }
                }
                Spacer(minLength: 8)
                Button(recording ? "Cancel" : "Record new") {
                    recording ? stopRecording() : startRecording()
                }
                .buttonStyle(.stamp(.default, size: .sm))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Shortcut \(KeyboardShortcutManager.displayString(for: shortcut))")

            if let message {
                Text(message).font(Stamp.small).foregroundColor(Stamp.alert)
            }
        }
        .onDisappear { stopRecording() }
    }

    /// "command+shift+p" → ["⇧", "⌘", "P"]
    private var keyCaps: [String] {
        let display = KeyboardShortcutManager.displayString(for: shortcut)
        let modifiers = display.prefix { "⌃⌥⇧⌘".contains($0) }.map(String.init)
        let key = String(display.dropFirst(modifiers.count))
        return modifiers + (key.isEmpty ? [] : [key])
    }

    private func startRecording() {
        message = nil
        recording = true
        Self.isRecording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
            if event.keyCode == 53 && modifiers.isEmpty { // Esc alone cancels
                stopRecording()
                return nil
            }
            if let recorded = KeyboardShortcutManager.shortcutString(keyCode: event.keyCode, modifiers: modifiers) {
                shortcut = recorded
                stopRecording()
            } else {
                message = "Use a modifier (⌘, ⌥, ⌃ or ⇧) plus one key, or a function key."
            }
            return nil // keep the keys from typing into other fields
        }
    }

    private func stopRecording() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        recording = false
        Self.isRecording = false
    }
}
