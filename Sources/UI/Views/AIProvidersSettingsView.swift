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
        StampSettingsPage(
            title: "AI providers",
            subtitle: "Choose where your text is sent."
        ) {
            HStack(alignment: .top, spacing: 18) {
                providerCard(.ollama, note: "Runs on this Mac. Your text never leaves it.") {
                    StampLabeled(label: "Server address") {
                        TextField(AIProvider.ollama.defaultURL, text: $ollamaURL)
                            .stampField()
                    }
                }
                providerCard(.openai, note: "Sends text to OpenAI. Check your company's policy first.") {
                    VStack(alignment: .leading, spacing: 12) {
                        StampLabeled(label: "API key", hint: "Stored in your Keychain") {
                            SecureField("sk-…", text: $openAIAPIKey)
                                .stampField()
                        }
                        StampLabeled(label: "Server address") {
                            TextField(AIProvider.openai.defaultURL, text: $openAIURL)
                                .stampField()
                        }
                    }
                }
            }
        } footer: {
            Button("Cancel") { dismiss() }
                .buttonStyle(.stamp(.default))
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
            .buttonStyle(.stamp(.primary))
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
                Text(provider.displayName).font(Stamp.title).foregroundColor(Stamp.ink)
                Spacer()
                if isActive {
                    StampBadge(text: "Active", tone: .sky)
                } else {
                    Button("Make active") { appState.setProvider(provider) }
                        .buttonStyle(.stamp(.default, size: .sm))
                }
            }
            Text(note)
                .font(Stamp.small)
                .foregroundColor(Stamp.inkMuted)
                .fixedSize(horizontal: false, vertical: true)

            fields()

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                statusText(for: provider)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("Test connection") {
                    Task { await test(provider) }
                }
                .buttonStyle(.stamp(.default, size: .sm))
                .fixedSize()
                .disabled(status[provider] == .testing)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .stampSurface(fill: Stamp.paperRaised, radius: Stamp.radiusLg,
                      stroke: isActive ? Stamp.stroke2 : Stamp.stroke1, shadow: isActive ? .lg : .md)
    }

    @ViewBuilder
    private func statusText(for provider: AIProvider) -> some View {
        switch status[provider] {
        case .none:
            Text(" ").font(Stamp.small)
        case .testing:
            Text("Connecting…").font(Stamp.small).foregroundColor(Stamp.inkSubtle)
        case .connected(let count):
            Label("Connected · \(count) models", systemImage: "checkmark.circle")
                .font(Stamp.small.weight(.bold))
                .foregroundColor(Stamp.ink)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.circle")
                .font(Stamp.small)
                .foregroundColor(Stamp.alert)
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
