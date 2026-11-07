import SwiftUI
import AppKit

// MARK: - Proofreading settings
/// Provider and model apply right away (like in the menu bar panel).
/// Shortcut, review mode and instructions are drafts until Save changes, so Cancel really cancels.
struct ProofreadingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editedPrompt: String = ""
    @State private var editedShortcut: String = ""
    @State private var editedShowDialog: Bool = true

    var body: some View {
        FocusSettingsPage(
            title: "Proofreading",
            subtitle: "Pick a model and how fixes come back to you."
        ) {
            HStack(alignment: .top, spacing: 16) {
                FocusSection(title: "Model") {
                    VStack(alignment: .leading, spacing: 12) {
                        FocusLabeled(label: "Provider") {
                            FocusTabs(
                                options: AIProvider.allCases.map { (value: $0, label: $0.displayName) },
                                selection: Binding(
                                    get: { appState.proofreadingProvider },
                                    set: { appState.setProvider($0) }
                                )
                            )
                            .fixedSize()
                        }
                        FocusLabeled(label: "Model", hint: modelHint) {
                            if appState.modelChoices.isEmpty {
                                Text("No models found")
                                    .font(Focus.control)
                                    .foregroundColor(Focus.text3)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .focusField()
                            } else {
                                FocusPicker(
                                    options: appState.modelChoices,
                                    selection: Binding(
                                        get: { appState.proofreadingModel },
                                        set: { appState.updateCurrentModel($0) }
                                    ),
                                    title: { $0 }
                                )
                            }
                        }
                    }
                }

                FocusSection(title: "Shortcut", subtitle: "Press it with text selected in any app.") {
                    VStack(alignment: .leading, spacing: 10) {
                        ShortcutRecorder(shortcut: $editedShortcut)
                        if let error = appState.shortcutError {
                            Text(error).font(.system(size: 12)).foregroundColor(Focus.risk)
                        }
                    }
                }
            }

            FocusSection(title: "When a fix is ready") {
                FocusTabs(
                    options: [(value: true, label: "Show me first"), (value: false, label: "Replace right away")],
                    selection: $editedShowDialog
                )
                .fixedSize()
            }

            FocusSection(title: "Instructions", subtitle: "Sent to the model before your text.") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $editedPrompt)
                        .font(Focus.mono)
                        .foregroundColor(Focus.text)
                        .frame(height: 120)
                        .focusTextArea()
                        .accessibilityLabel("Proofreading instructions")
                    HStack {
                        Spacer()
                        Button("Reset to default") {
                            editedPrompt = ConfigurationManager.defaultPrompt
                        }
                        .buttonStyle(.focus(.ghost))
                        .disabled(editedPrompt == ConfigurationManager.defaultPrompt)
                    }
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.focus())
                .keyboardShortcut(.cancelAction)
            Button("Save changes") { save() }
                .buttonStyle(.focus(.primary))
                .keyboardShortcut("s", modifiers: .command)
        }
        .onAppear {
            editedPrompt = appState.currentPrompt
            editedShortcut = appState.keyboardShortcut
            editedShowDialog = appState.showDialog
            // A leftover error from an earlier, cancelled edit no longer applies
            if KeyboardShortcutManager.isValidShortcut(appState.keyboardShortcut) {
                appState.shortcutError = nil
            }
        }
    }

    private var modelHint: String? {
        if appState.isSelectedModelMissing {
            return "“\(appState.proofreadingModel)” isn't installed. Pick another."
        }
        return "Applies right away."
    }

    private func save() {
        appState.updateCurrentPrompt(editedPrompt)
        if editedShowDialog != appState.showDialog {
            appState.updateShowDialog(editedShowDialog)
        }
        if editedShortcut != appState.keyboardShortcut {
            appState.updateKeyboardShortcut(editedShortcut)
        }
        // Keep the window open so the user can correct an invalid shortcut
        if appState.shortcutError == nil {
            dismiss()
        }
    }
}
