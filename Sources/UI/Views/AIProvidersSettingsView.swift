import SwiftUI
import AppKit

// MARK: - AI Providers Settings Content
struct AIProvidersSettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isURLFieldFocused: Bool
    @State private var selectedProviderForConfig: AIProvider = .ollama
    @State private var connectionStatus: String = ""
    @State private var isTestingConnection: Bool = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Content area
            Form {
                Picker("Configure Provider:", selection: $selectedProviderForConfig) {
                    ForEach(AIProvider.allCases, id: \.self) { provider in
                        Text(provider.displayName).tag(provider)
                    }
                }
                .pickerStyle(.menu)
                
                switch selectedProviderForConfig {
                case .ollama:
                    TextField("URL:", text: $appState.ollamaURL)
                        .focused($isURLFieldFocused)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green :
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120)

                        Spacer()

                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .ollama, url: appState.ollamaURL, apiKey: "")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }

                case .openai:
                    TextField("URL:", text: $appState.openAIURL)
                        .focused($isURLFieldFocused)
                    SecureField("API Key:", text: $appState.openAIAPIKey)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green :
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120)

                        Spacer()

                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .openai, url: appState.openAIURL, apiKey: appState.openAIAPIKey)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }

                case .qwen:
                    TextField("Token File Path:", text: $appState.qwenTokenFilePath)
                        .focused($isURLFieldFocused)
                    Text("Enter the path to your Qwen OAuth token file (e.g., ~/.qwen/token.json)")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green :
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120)

                        Spacer()

                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }

                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .qwen, url: "", apiKey: appState.qwenTokenFilePath)
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)
            
            // Bottom bar with action buttons
            Divider()
            
            HStack(spacing: 12) {
                Spacer()
                
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.escape)
                
                Button("OK") {
                    switch selectedProviderForConfig {
                    case .ollama:
                        appState.updateProviderURL(appState.ollamaURL)
                    case .openai:
                        appState.updateProviderURL(appState.openAIURL)
                        appState.updateOpenAIAPIKey(appState.openAIAPIKey)
                    case .qwen:
                        appState.updateQwenTokenFilePath(appState.qwenTokenFilePath)
                    }
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            isURLFieldFocused = true
        }
    }
    
    private func testConnection(provider: AIProvider, url: String, apiKey: String) async {
        await MainActor.run {
            connectionStatus = "Connecting..."
            isTestingConnection = true
        }

        do {
            let configuration = AIConfiguration(
                ollamaURL: provider == .ollama ? url : "http://127.0.0.1:11434",
                openAIURL: provider == .openai ? url : "https://api.openai.com",
                openAIAPIKey: provider == .openai ? apiKey : "",
                qwenTokenFilePath: provider == .qwen ? apiKey : ""
            )

            let service = AIServiceFactory.createService(for: provider, configuration: configuration)
            let models = try await service.listModels()

            await MainActor.run {
                connectionStatus = "Connected (\(models.count) models)"
                isTestingConnection = false
            }
        } catch {
            await MainActor.run {
                connectionStatus = "Error: \(error.localizedDescription)"
                isTestingConnection = false
            }
        }
    }
}

#Preview("AI Providers Settings Content") {
    AIProvidersSettingsView()
        .frame(width: 500, height: 400)
}
