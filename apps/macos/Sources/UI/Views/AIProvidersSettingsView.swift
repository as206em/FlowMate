import SwiftUI
import AppKit

// MARK: - AI provider settings
/// Both providers side by side. Addresses and the API key are drafts until Save changes.
struct AIProvidersSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var ollamaURL: String = ""
    @State private var openAIURL: String = ""
    @State private var openAIAPIKey: String = ""
    @State private var status: [AIProvider: TestStatus] = [:]

    enum TestStatus: Equatable {
        case testing
        case connected(Int)
        case failed(String)
    }

    var body: some View {
        FocusSettingsPage(
            title: "AI providers",
            subtitle: "Choose where your text is sent."
        ) {
            HStack(alignment: .top, spacing: 16) {
                providerCard(.ollama, note: "Runs on this Mac. Your text never leaves it.") {
                    FocusLabeled(label: "Server address") {
                        TextField(AIProvider.ollama.defaultURL, text: $ollamaURL)
                            .focusField()
                    }
                }
                providerCard(.openai, note: "Sends text to OpenAI. Check your company's policy first.") {
                    VStack(alignment: .leading, spacing: 12) {
                        FocusLabeled(label: "API key", hint: "Stored in your Keychain") {
                            SecureField("sk-…", text: $openAIAPIKey)
                                .focusField()
                        }
                        FocusLabeled(label: "Server address") {
                            TextField(AIProvider.openai.defaultURL, text: $openAIURL)
                                .focusField()
                        }
                    }
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.focus())
                .keyboardShortcut(.cancelAction)
            Button("Save changes") {
                // Save each provider's own fields; never write one provider's URL into the other
                appState.updateProviderSettings(
                    ollamaURL: ollamaURL,
                    openAIURL: openAIURL,
                    openAIAPIKey: openAIAPIKey
                )
                dismiss()
            }
            .buttonStyle(.focus(.primary))
            .keyboardShortcut("s", modifiers: .command)
        }
        .onAppear {
            ollamaURL = appState.ollamaURL
            openAIURL = appState.openAIURL
            openAIAPIKey = appState.openAIAPIKey
        }
    }

    private func providerCard<Fields: View>(_ provider: AIProvider, note: String, @ViewBuilder fields: () -> Fields) -> some View {
        let isActive = appState.proofreadingProvider == provider
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(provider.displayName).font(Focus.header).foregroundColor(Focus.text)
                Spacer()
                if isActive {
                    FocusStatusLabel(text: "Active", tone: .ok)
                } else {
                    Button("Make active") { appState.setProvider(provider) }
                        .buttonStyle(.focus())
                }
            }
            Text(note)
                .font(Focus.meta)
                .foregroundColor(Focus.text3)
                .fixedSize(horizontal: false, vertical: true)

            fields()

            HStack(alignment: .center, spacing: 8) {
                statusText(for: provider)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Test connection") {
                    Task { await test(provider) }
                }
                .buttonStyle(.focus())
                .fixedSize()
                .disabled(status[provider] == .testing)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: Focus.radiusPanel).fill(Focus.raised))
        .overlay(
            RoundedRectangle(cornerRadius: Focus.radiusPanel)
                .strokeBorder(isActive ? Focus.lineStrong : Focus.hairline, lineWidth: 1)
        )
    }

    @ViewBuilder
    private func statusText(for provider: AIProvider) -> some View {
        switch status[provider] {
        case .none:
            Text(" ").font(Focus.meta)
        case .testing:
            Text("Connecting…").font(Focus.meta).foregroundColor(Focus.text3)
        case .connected(let count):
            Label("Connected · \(count) models", systemImage: "checkmark.circle")
                .font(Focus.meta.weight(.medium))
                .foregroundColor(Focus.ok)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(Focus.meta)
                .foregroundColor(Focus.risk)
                .lineLimit(3)
        }
    }

    private func test(_ provider: AIProvider) async {
        status[provider] = .testing
        let configuration = AIConfiguration(
            ollamaURL: provider == .ollama ? ollamaURL : AIProvider.ollama.defaultURL,
            openAIURL: provider == .openai ? openAIURL : AIProvider.openai.defaultURL,
            openAIAPIKey: openAIAPIKey
        )
        do {
            let models = try await AIServiceFactory.createService(for: provider, configuration: configuration).listModels()
            status[provider] = .connected(models.count)
        } catch {
            status[provider] = .failed(error.localizedDescription)
        }
    }
}
