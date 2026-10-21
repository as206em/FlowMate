import SwiftUI

struct ProofreadingDialog: View {
    @EnvironmentObject private var appState: AppState
    @State private var monitor: Any?
    private let keyMonitorService: KeyMonitorServiceProtocol = KeyMonitorService()

    // Use computed property to bind to AppState's persistent setting
    private var showDiff: Binding<Bool> {
        Binding(
            get: { appState.showDiffByDefault },
            set: { appState.updateShowDiffByDefault($0) }
        )
    }

    var body: some View {
        VStack(spacing: 8) {
            if appState.isProcessing {
                processingView
            } else if let error = appState.proofreadingError {
                errorView(error)
            } else {
                resultView
            }
        }
        .frame(minWidth: 560, idealWidth: 800, maxWidth: .infinity, minHeight: 360, idealHeight: 500, maxHeight: .infinity)
        .onAppear {
            setupKeyMonitor()
        }
        .onDisappear {
            removeKeyMonitor()
        }
    }

    // MARK: - States

    private var processingView: some View {
        VStack(spacing: 16) {
            LoadingView()
            Button("Cancel") {
                appState.cancelProofreading()
            }
            .padding(.bottom, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundColor(.orange)
            Text("Proofreading failed")
                .font(.title3)
                .fontWeight(.semibold)
            Text(error)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .textSelection(.enabled)
                .frame(maxWidth: 480)
            Spacer()
            HStack(spacing: 12) {
                Button("Open Settings") {
                    appState.closeProofreadingDialog()
                    appState.showSettings(nil)
                }
                Spacer()
                Button("Close") {
                    appState.closeProofreadingDialog()
                }
                Button("Retry") {
                    appState.retryProofreading()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding([.horizontal, .bottom], 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var resultView: some View {
        VStack(spacing: 8) {
            HStack {
                Toggle("Show Differences", isOn: showDiff)
                    .toggleStyle(SwitchToggleStyle())
                Text(showDiff.wrappedValue ? "Turn off to edit the result" : "You can edit the result before copying or replacing")
                    .font(.caption)
                    .foregroundColor(.secondary)
                Spacer()
                if appState.correctedText == appState.originalText {
                    Label("No changes needed", systemImage: "checkmark.seal")
                        .font(.caption)
                        .foregroundColor(.green)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if showDiff.wrappedValue && !appState.originalText.isEmpty {
                DiffHighlightView(
                    originalText: appState.originalText,
                    correctedText: appState.correctedText
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // Editable result: Copy and Replace use the edited text
                TextEditor(text: $appState.correctedText)
                    .font(.system(.body, design: .default))
                    .background(Color(NSColor.textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color(NSColor.separatorColor), lineWidth: 0.5)
                    )
                    .cornerRadius(6)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            HStack(spacing: 12) {
                Button("Retry") {
                    appState.retryProofreading()
                }
                .help("Proofread the original text again")

                Spacer()

                Button("Close") {
                    appState.closeProofreadingDialog()
                }

                if appState.canReplace {
                    Button("Copy") {
                        appState.copyResult()
                        appState.closeProofreadingDialog()
                    }

                    Button("Replace") {
                        appState.replaceInSourceApp()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Paste the result over the selected text (⌘↩)")
                } else {
                    Button("Copy") {
                        appState.copyResult()
                        appState.closeProofreadingDialog()
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Copy the result to the clipboard (⌘↩)")
                }
            }
            .padding(.bottom, 16)
            .padding(.horizontal, 16)
        }
    }

    // MARK: - Helpers

    private func setupKeyMonitor() {
        monitor = keyMonitorService.setupEscapeKeyMonitor(dismissAction: {
            // Only react to Esc pressed in this window, not in Settings
            guard WindowManager.shared.isKeyWindow(id: "proofreading-dialog") else { return }
            if appState.isProcessing {
                appState.cancelProofreading()
            } else {
                appState.closeProofreadingDialog()
            }
        })
    }

    private func removeKeyMonitor() {
        keyMonitorService.removeKeyMonitor(monitor)
        self.monitor = nil
    }
}
