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
        StampSettingsPage(
            title: "Proofreading",
            subtitle: "Pick a model and how fixes come back to you."
        ) {
            HStack(alignment: .top, spacing: 18) {
                StampCard(title: "Model") {
                    VStack(alignment: .leading, spacing: 12) {
                        StampSegmented(
                            label: "Provider",
                            options: AIProvider.allCases.map { .init(value: $0, label: $0.displayName) },
                            selection: Binding(
                                get: { appState.proofreadingProvider },
                                set: { appState.setProvider($0) }
                            )
                        )
                        StampLabeled(label: "Model", hint: modelHint) {
                            if appState.modelChoices.isEmpty {
                                Text("No models found")
                                    .font(Stamp.body)
                                    .foregroundColor(Stamp.inkSubtle)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                                    .stampSurface(fill: Stamp.paperSunk, shadow: .none)
                            } else {
                                StampPicker(
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

                StampCard(title: "Shortcut") {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Press it with text selected in any app.")
                            .font(Stamp.small)
                            .foregroundColor(Stamp.inkMuted)
                        ShortcutRecorder(shortcut: $editedShortcut)
                        if let error = appState.shortcutError {
                            Text(error).font(Stamp.small).foregroundColor(Stamp.alert)
                        }
                    }
                }
            }

            StampCard(title: "When a fix is ready") {
                StampSegmented(
                    options: [
                        .init(value: true, label: "Show me first", tint: Stamp.sky),
                        .init(value: false, label: "Replace right away", tint: Stamp.mint)
                    ],
                    selection: $editedShowDialog
                )
            }

            StampCard(title: "Instructions") {
                VStack(alignment: .leading, spacing: 10) {
                    TextEditor(text: $editedPrompt)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(Stamp.ink)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .frame(height: 110)
                        .background(RoundedRectangle(cornerRadius: Stamp.radiusMd).fill(Stamp.paperSunk))
                        .overlay(RoundedRectangle(cornerRadius: Stamp.radiusMd).strokeBorder(Stamp.line, lineWidth: Stamp.stroke1))
                        .accessibilityLabel("Proofreading instructions")
                    HStack {
                        Text("Sent to the model before your text.")
                            .font(Stamp.small)
                            .foregroundColor(Stamp.inkSubtle)
                        Spacer()
                        Button("Reset to default") {
                            editedPrompt = ConfigurationManager.defaultPrompt
                        }
                        .buttonStyle(.stamp(.ghost, size: .sm))
                        .disabled(editedPrompt == ConfigurationManager.defaultPrompt)
                    }
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.stamp(.default))
                .keyboardShortcut(.cancelAction)
            Button("Save changes") { save() }
                .buttonStyle(.stamp(.primary))
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
