import SwiftUI

// MARK: - Dictation settings
/// Settings › Dictation: the mic buttons on task and project titles and descriptions.
/// Changes are drafts until Save changes, like Proofreading.
struct DictationSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var draft = DictationSettings()
    @State private var micAccess: MicrophoneAccess = .notAsked

    private let permission = SystemMicrophonePermission()

    var body: some View {
        FocusSettingsPage(
            title: "Dictation",
            subtitle: "Speak a task's title or description. Your words appear as you talk, then get proofread."
        ) {
            banners

            FocusSection(title: "Mic buttons", subtitle: "On titles and descriptions of tasks and projects.") {
                VStack(alignment: .leading, spacing: 14) {
                    toggle("Show the mic buttons",
                           hint: "Click the mic to start, click again to stop. Esc takes the dictation back out.",
                           isOn: $draft.enabled)
                    microphoneRow
                }
            }

            HStack(alignment: .top, spacing: 16) {
                FocusSection(title: "Transcription", subtitle: "OpenAI, with the key from AI providers.") {
                    VStack(alignment: .leading, spacing: 12) {
                        FocusLabeled(label: "Model", hint: modelHint) {
                            FocusTabs(
                                options: DictationSettings.models.map { (value: $0.id, label: $0.label) },
                                selection: $draft.model
                            )
                            .fixedSize()
                        }
                        FocusLabeled(label: "Language") {
                            FocusPicker(
                                options: DictationSettings.languages.map(\.code),
                                selection: $draft.language,
                                title: { code in DictationSettings.languages.first { $0.code == code }?.name ?? code }
                            )
                        }
                    }
                }

                FocusSection(title: "When you stop") {
                    toggle("Proofread what I said",
                           hint: "Fixes punctuation, grammar and filler words with your Proofreading model (\(appState.proofreadingProvider.displayName) · \(appState.proofreadingModel)). ⌘Z brings back your exact words.",
                           isOn: $draft.proofreadAfter)
                }
            }

            FocusSection(title: "Instructions",
                         subtitle: "Sent with every dictation and proofreading: what you dictate and how it should read.") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $draft.instructions)
                        .font(Focus.mono)
                        .foregroundColor(Focus.text)
                        .frame(height: 90)
                        .focusTextArea()
                        .accessibilityLabel("Dictation instructions")
                    HStack {
                        Spacer()
                        Button("Reset to default") { draft.instructions = DictationSettings.defaultInstructions }
                            .buttonStyle(.focus(.ghost))
                            .disabled(draft.instructions == DictationSettings.defaultInstructions)
                    }
                }
            }

            FocusSection(title: "Vocabulary",
                         subtitle: "Names and terms to spell exactly, one per line: projects, products, people, jargon.") {
                TextEditor(text: $draft.vocabulary)
                    .font(Focus.mono)
                    .foregroundColor(Focus.text)
                    .frame(height: 90)
                    .focusTextArea()
                    .accessibilityLabel("Dictation vocabulary")
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.focus())
                .keyboardShortcut(.cancelAction)
            Button("Save changes") {
                appState.updateDictationSettings(draft)
                dismiss()
            }
            .buttonStyle(.focus(.primary))
            .keyboardShortcut("s", modifiers: .command)
        }
        .onAppear {
            draft = appState.dictationSettings
            micAccess = permission.status
        }
    }

    private var modelHint: String {
        draft.model == DictationSettings.liveModel
            ? "Words appear as you speak."
            : "Text appears after each pause; can be more accurate."
    }

    @ViewBuilder
    private var banners: some View {
        if draft.enabled && appState.openAIAPIKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            FocusBanner(
                tone: .risk,
                systemImage: "key",
                title: "Add an OpenAI API key",
                message: "Dictation uses OpenAI's live transcription. Add your key in AI providers. Proofreading uses the provider picked in Proofreading."
            )
        }
    }

    @ViewBuilder
    private var microphoneRow: some View {
        HStack(spacing: 10) {
            Image(systemName: micAccess == .denied ? "mic.slash" : "mic")
                .foregroundColor(micAccess == .denied ? Focus.risk : Focus.text2)
            VStack(alignment: .leading, spacing: 2) {
                Text("Microphone").font(Focus.control).foregroundColor(Focus.text)
                Text(micText).font(.system(size: 12)).foregroundColor(Focus.text3)
            }
            Spacer()
            switch micAccess {
            case .notAsked:
                Button("Allow…") {
                    Task {
                        _ = await permission.request()
                        micAccess = permission.status
                    }
                }
                .buttonStyle(.focus())
            case .denied:
                Button("Open System Settings") { SystemMicrophonePermission.openSystemSettings() }
                    .buttonStyle(.focus())
            case .allowed:
                EmptyView()
            }
        }
        .frame(maxWidth: 520, alignment: .leading)
    }

    private var micText: String {
        switch micAccess {
        case .allowed: return "Allowed."
        case .notAsked: return "macOS asks the first time you dictate."
        case .denied: return "Blocked. Turn FlowMate on in System Settings › Privacy & Security › Microphone."
        }
    }

    private func toggle(_ title: String, hint: String, isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(Focus.control).foregroundColor(Focus.text)
                Text(hint).font(.system(size: 12)).foregroundColor(Focus.text3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .toggleStyle(.focus)
        .frame(maxWidth: 520, alignment: .leading)
    }
}
