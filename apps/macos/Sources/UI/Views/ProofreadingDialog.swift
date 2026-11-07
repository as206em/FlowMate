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
        VStack(spacing: 0) {
            if appState.isProcessing {
                processingView
            } else if let error = appState.proofreadingError {
                errorView(error)
            } else {
                resultView
            }
        }
        .frame(minWidth: 560, idealWidth: 800, maxWidth: .infinity, minHeight: 360, idealHeight: 500, maxHeight: .infinity)
        .background(Focus.canvas)
        .focusLight()
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
            .buttonStyle(.focus())
            .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func errorView(_ error: String) -> some View {
        VStack(spacing: 0) {
            VStack(spacing: 12) {
                Spacer()
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 28))
                    .foregroundColor(Focus.risk)
                Text("Proofreading failed")
                    .font(Focus.pageTitle)
                    .foregroundColor(Focus.text)
                Text(error)
                    .font(Focus.body)
                    .foregroundColor(Focus.text2)
                    .multilineTextAlignment(.center)
                    .textSelection(.enabled)
                    .frame(maxWidth: 480)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            actionBar {
                Button("Open Settings") {
                    appState.closeProofreadingDialog()
                    appState.showSettings(nil)
                }
                .buttonStyle(.focus(.ghost))
                Spacer()
                Button("Close") {
                    appState.closeProofreadingDialog()
                }
                .buttonStyle(.focus())
                Button("Retry") {
                    appState.retryProofreading()
                }
                .buttonStyle(.focus(.primary))
                .keyboardShortcut(.return)
            }
        }
    }

    private var resultView: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Toggle(isOn: showDiff) {
                    Text("Show differences").font(Focus.control).foregroundColor(Focus.text)
                }
                .toggleStyle(.focus)
                .fixedSize()
                Text(showDiff.wrappedValue ? "Turn off to edit the result" : "You can edit the result before copying or replacing")
                    .font(Focus.meta)
                    .foregroundColor(Focus.text3)
                    .lineLimit(1)
                Spacer()
                if appState.correctedText == appState.originalText {
                    Label("No changes needed", systemImage: "checkmark.circle.fill")
                        .font(Focus.meta.weight(.medium))
                        .foregroundColor(Focus.ok)
                }
            }
            .padding(.horizontal, 20)
            .frame(height: 52)

            Group {
                if showDiff.wrappedValue && !appState.originalText.isEmpty {
                    DiffHighlightView(
                        originalText: appState.originalText,
                        correctedText: appState.correctedText
                    )
                } else {
                    // Editable result: Copy and Replace use the edited text
                    TextEditor(text: $appState.correctedText)
                        .font(Focus.body)
                        .foregroundColor(Focus.text)
                        .lineSpacing(3)
                        .focusTextArea()
                        .padding(.horizontal, 20)
                        .padding(.bottom, 12)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar {
                Button("Retry") {
                    appState.retryProofreading()
                }
                .buttonStyle(.focus(.ghost))
                .help("Proofread the original text again")

                Spacer()

                Button("Close") {
                    appState.closeProofreadingDialog()
                }
                .buttonStyle(.focus())

                if appState.canReplace {
                    Button("Copy") {
                        appState.copyResult()
                        appState.closeProofreadingDialog()
                    }
                    .buttonStyle(.focus())

                    Button("Replace") {
                        appState.replaceInSourceApp()
                    }
                    .buttonStyle(.focus(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Paste the result over the selected text (⌘↩)")
                } else {
                    Button("Copy") {
                        appState.copyResult()
                        appState.closeProofreadingDialog()
                    }
                    .buttonStyle(.focus(.primary))
                    .keyboardShortcut(.return, modifiers: .command)
                    .help("Copy the result to the clipboard (⌘↩)")
                }
            }
        }
    }

    /// Bottom bar with a hairline above it
    private func actionBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 8) { content() }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { FocusDivider() }
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
