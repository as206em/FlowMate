import SwiftUI
import AppKit

// MARK: - Proofreading Settings Content
struct ProofreadingSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var editedPrompt: String = ""
    // Local copy: the shortcut only changes on Return or OK, so Cancel really cancels
    @State private var editedShortcut: String = ""
    @FocusState private var isURLFieldFocused: Bool
    @FocusState private var isPromptEditorFocused: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Group {
                        HStack {
                            Text("Provider:")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $appState.proofreadingProvider) {
                                ForEach(AIProvider.allCases, id: \.self) { provider in
                                    Text(provider.displayName).tag(provider)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: appState.proofreadingProvider) { provider in
                                appState.setProvider(provider)
                            }
                        }
                        
                        HStack {
                            Text("Model:")
                                .frame(width: 80, alignment: .leading)
                            Picker("", selection: $appState.proofreadingModel) {
                                ForEach(appState.modelChoices, id: \.self) { model in
                                    Text(model).tag(model)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(maxWidth: .infinity)
                            .onChange(of: appState.proofreadingModel) { newValue in
                                appState.updateCurrentModel(newValue)
                            }
                        }
                        
                        HStack {
                            Text("Shortcut:")
                                .frame(width: 80, alignment: .leading)
                            TextField("", text: $editedShortcut)
                                .onSubmit {
                                    appState.updateKeyboardShortcut(editedShortcut)
                                }
                        }

                        if let shortcutError = appState.shortcutError {
                            Text(shortcutError)
                                .font(.caption)
                                .foregroundColor(.red)
                                .padding(.leading, 88)
                        }
                        
                        HStack {
                            Text("Show Dialog:")
                                .frame(width: 80, alignment: .leading)
                            Toggle("", isOn: $appState.showDialog)
                                .labelsHidden()
                                .onChange(of: appState.showDialog) { newValue in
                                    appState.updateShowDialog(newValue)
                                }
                            Text("Display results in dialog before replacing")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            Spacer()
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Proofreading Instructions:")
                                .font(.headline)
                                .foregroundColor(.primary)
                            Spacer()
                            Button("Reset to Default") {
                                editedPrompt = ConfigurationManager.defaultPrompt
                            }
                            .disabled(editedPrompt == ConfigurationManager.defaultPrompt)
                            .help("Restore the built-in instructions. Press OK to save.")
                        }
                        
                        TextEditor(text: $editedPrompt)
                            .font(.system(size: 13, design: .monospaced))
                            .padding(8)
                            .background(Color(.textBackgroundColor))
                            .cornerRadius(6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .frame(height: 120)
                            .focused($isPromptEditorFocused)
                    }
                }
                .padding(20)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            // Bottom bar with action buttons
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("OK") {
                    appState.updateCurrentPrompt(editedPrompt)
                    if editedShortcut != appState.keyboardShortcut {
                        appState.updateKeyboardShortcut(editedShortcut)
                    }
                    // Keep the window open so the user can correct an invalid shortcut
                    if appState.shortcutError == nil {
                        dismiss()
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            editedPrompt = appState.currentPrompt
            editedShortcut = appState.keyboardShortcut
            // A leftover error from an earlier, cancelled edit no longer applies
            if KeyboardShortcutManager.isValidShortcut(appState.keyboardShortcut) {
                appState.shortcutError = nil
            }
            isURLFieldFocused = true
        }
    }
}

#Preview("Proofreading Settings Content") {
    ProofreadingSettingsView()
        .environmentObject(AppState(statusManager: StatusManager()))
        .frame(width: 500, height: 400)
}
