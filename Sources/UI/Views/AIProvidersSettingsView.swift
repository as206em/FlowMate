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
    // Local copies: edits only take effect on OK, so Cancel really cancels
    @State private var ollamaURL: String = ""
    @State private var openAIURL: String = ""
    @State private var openAIAPIKey: String = ""
    
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
                
                if selectedProviderForConfig == .ollama {
                    TextField("URL:", text: $ollamaURL)
                        .focused($isURLFieldFocused)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green : 
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120) // Fixed width to prevent layout shifts
                        
                        Spacer()
                        
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .ollama, url: ollamaURL, apiKey: "")
                            }
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.regular)
                        .disabled(isTestingConnection)
                    }
                } else {
                    TextField("URL:", text: $openAIURL)
                        .focused($isURLFieldFocused)
                    SecureField("API Key:", text: $openAIAPIKey)
                    HStack {
                        Text(connectionStatus)
                            .font(.caption)
                            .foregroundColor(connectionStatus.contains("Connected") ? .green : 
                                           connectionStatus.contains("Connecting") ? .orange : .red)
                            .frame(minWidth: 120) // Fixed width to prevent layout shifts
                        
                        Spacer()
                        
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        
                        Button("Test Connection") {
                            Task {
                                await testConnection(provider: .openai, url: openAIURL, apiKey: openAIAPIKey)
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
                    // Save each provider's own fields; never write one provider's URL into the other
                    appState.updateProviderSettings(
                        ollamaURL: ollamaURL,
                        openAIURL: openAIURL,
                        openAIAPIKey: openAIAPIKey
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.return)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .onAppear {
            ollamaURL = appState.ollamaURL
            openAIURL = appState.openAIURL
            openAIAPIKey = appState.openAIAPIKey
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
                ollamaURL: provider == .ollama ? url : AIProvider.ollama.defaultURL,
                openAIURL: provider == .openai ? url : AIProvider.openai.defaultURL,
                openAIAPIKey: apiKey
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
