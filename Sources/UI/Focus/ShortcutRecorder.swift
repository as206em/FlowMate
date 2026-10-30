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
                        .font(Focus.control)
                        .foregroundColor(Focus.liveText)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.liveSoft))
                        .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.live, lineWidth: 1))
                } else if keyCaps.isEmpty {
                    Text("Off")
                        .font(Focus.control)
                        .foregroundColor(Focus.text3)
                        .padding(.horizontal, 12)
                        .frame(height: 36)
                        .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.lineStrong, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                } else {
                    ForEach(Array(keyCaps.enumerated()), id: \.offset) { _, cap in
                        Text(cap)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Focus.text)
                            .frame(minWidth: 36, minHeight: 36)
                            .padding(.horizontal, cap.count > 1 ? 8 : 0)
                            .background(RoundedRectangle(cornerRadius: Focus.radiusControl).fill(Focus.raised))
                            .overlay(RoundedRectangle(cornerRadius: Focus.radiusControl).strokeBorder(Focus.lineStrong, lineWidth: 1))
                            .shadow(color: .black.opacity(0.06), radius: 0, y: 1)
                    }
                }
                Spacer(minLength: 8)
                Button(recording ? "Cancel" : "Record new") {
                    recording ? stopRecording() : startRecording()
                }
                .buttonStyle(.focus())
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel(shortcut.isEmpty ? "Shortcut off" : "Shortcut \(KeyboardShortcutManager.displayString(for: shortcut))")

            if let message {
                Text(message).font(.system(size: 12)).foregroundColor(Focus.risk)
            }
        }
        .onDisappear { stopRecording() }
    }

    /// "command+shift+p" → ["⇧", "⌘", "P"]
    private var keyCaps: [String] {
        guard !shortcut.isEmpty else { return [] }
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
