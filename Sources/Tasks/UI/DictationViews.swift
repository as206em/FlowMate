import SwiftUI

/// The mic button on a title or description. Hidden unless Settings › Dictation is on.
/// Click to start, click again to stop; Esc takes the dictation back out.
struct DictationMicButton: View {
    @ObservedObject private var dictation = DictationController.shared
    let targetId: String
    var size: CGFloat = 28
    /// Builds the target when you click, so it starts from the field's current text
    let makeTarget: () -> DictationController.Target

    @State private var hovering = false

    var body: some View {
        if dictation.settings.enabled {
            let active = dictation.isActive(targetId)
            let listening = active && dictation.phase == .listening
            Button {
                if listening { dictation.stop() } else { dictation.toggle(makeTarget()) }
            } label: {
                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(listening ? Focus.liveSoft : (hovering ? Focus.hover : .clear))
                    if listening {
                        Circle()
                            .fill(Focus.liveGlow)
                            .frame(width: size * 0.62, height: size * 0.62)
                            .scaleEffect(0.7 + CGFloat(dictation.level) * 0.7)
                            .animation(.easeOut(duration: 0.1), value: dictation.level)
                    }
                    if active && !listening {
                        ProgressView().controlSize(.small).scaleEffect(0.7)
                    } else {
                        Image(systemName: listening ? "mic.fill" : "mic")
                            .font(.system(size: size * 0.46, weight: .semibold))
                            .foregroundColor(listening ? Focus.liveText : (hovering ? Focus.text : Focus.text2))
                    }
                }
                .frame(width: size, height: size)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .disabled(dictation.isBusy && !active)
            .help(help(active: active, listening: listening))
            .accessibilityLabel(listening ? "Stop dictation" : "Dictate")
        }
    }

    private func help(active: Bool, listening: Bool) -> String {
        if listening { return "Stop dictation (Esc takes it back)" }
        if active { return dictation.phase == .proofreading ? "Proofreading…" : "Finishing…" }
        return dictation.unavailableReason ?? "Dictate"
    }
}

/// One line under a field: listening, proofreading, or what went wrong.
struct DictationStatusLine: View {
    @ObservedObject private var dictation = DictationController.shared
    let targetId: String

    var body: some View {
        if let error = dictation.error, error.targetId == targetId {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").foregroundColor(Focus.risk)
                Text(error.message).foregroundColor(Focus.text2).fixedSize(horizontal: false, vertical: true)
                Button("Dismiss") { dictation.clearError() }
                    .buttonStyle(.plain)
                    .foregroundColor(Focus.text3)
            }
            .font(.system(size: 12))
        } else if dictation.isActive(targetId) {
            HStack(spacing: 6) {
                switch dictation.phase {
                case .listening:
                    Circle().fill(Focus.live).frame(width: 6, height: 6)
                    Text("Listening. Click the mic to stop, Esc to cancel.")
                case .finishing:
                    Text("Finishing…")
                case .proofreading:
                    Text("Proofreading…")
                case .idle:
                    EmptyView()
                }
            }
            .font(.system(size: 12))
            .foregroundColor(Focus.text3)
        }
    }
}
