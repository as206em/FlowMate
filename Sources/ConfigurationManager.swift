import Foundation
import SwiftUI

@MainActor
class ConfigurationManager: ObservableObject {
    @Published private(set) var config: AppConfig
    let fileManager = FileManager.default
    private let configURL: URL
    
    public init(configURL: URL? = nil) {
        let actualConfigURL = configURL ?? Self.configDirectory.appendingPathComponent("config.json")
        self.configURL = actualConfigURL
        self.config = Self.loadConfiguration(from: actualConfigURL) ?? Self.defaultConfiguration
    }
    
    // MARK: - Private Methods
    
    public static var configDirectory: URL {
        let urls = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
        let appSupport = urls[0]
        return appSupport.appendingPathComponent("FlowMate")
    }
    
    private static var defaultConfiguration: AppConfig {
        return AppConfig(
            providers: ProvidersConfig(
                ollama: ProviderConfig(url: "http://127.0.0.1:11434", apiKey: nil),
                openai: ProviderConfig(url: "https://api.openai.com", apiKey: "")
            ),
            proofreading: ProofreadingConfig(
                selectedProvider: "ollama",
                defaultPrompt: "You are a text proofreader. Your task is to correct typos and grammar errors in the provided text while strictly preserving the original meaning, formatting, and style.",
                showDiffByDefault: true,
                keyboardShortcut: "command+.",
                model: "gemma3:4b"
            ),
            app: AppSettings()
        )
    }
    
    public static func loadConfiguration(from url: URL) -> AppConfig? {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: url.path) else {
            return nil
        }
        
        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            return try decoder.decode(AppConfig.self, from: data)
        } catch {
            print("Failed to load configuration: \(error)")
            return nil
        }
    }
    
    open func saveConfiguration() {
        do {
            // Ensure the directory exists
            let directory = configURL.deletingLastPathComponent()
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true, attributes: nil)
            
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(config)
            try data.write(to: configURL, options: .atomic)
        } catch {
            print("Failed to save configuration: \(error)")
        }
    }
    
    func updateConfigAndSave(updating: (inout AppConfig) -> Void) {
        var updatedConfig = config
        updating(&updatedConfig)
        config = updatedConfig
        saveConfiguration()
    }
    
    // MARK: - Public API - Scalable Feature-Level Updates
    
    // MARK: Feature Configuration - Proofreading (Primary API)
    
    /// Update proofreading configuration with a closure that modifies the config object
    /// Usage: configManager.updateProofreadingConfig { config in
    ///     config.selectedProvider = "openai"
    ///     config.defaultPrompt = "New prompt"
    /// }
    func updateProofreadingConfig(_ update: (inout ProofreadingConfig) -> Void) {
        updateConfigAndSave { config in
            update(&config.proofreading)
        }
    }
    
    /// Get current proofreading configuration
    func getProofreadingConfig() -> ProofreadingConfig {
        return config.proofreading
    }
    
    // MARK: App Configuration (Primary API)
    
    /// Update app settings with a closure that modifies the settings object
    /// Usage: configManager.updateAppSettings { settings in
    ///     settings.theme = "dark"
    ///     settings.autoCheckUpdates = false
    /// }
    func updateAppSettings(_ update: (inout AppSettings) -> Void) {
        updateConfigAndSave { config in
            update(&config.app)
        }
    }
    
    /// Get current app settings
    func getAppSettings() -> AppSettings {
        return config.app
    }
    
    // MARK: Provider Configuration (Primary API)
    
    /// Update provider configuration with a closure that modifies the providers object
    /// Usage: configManager.updateProvidersConfig { providers in
    ///     providers.ollama.url = "http://new-url:11434"
    ///     providers.openai.apiKey = "new-key"
    /// }
    func updateProvidersConfig(_ update: (inout ProvidersConfig) -> Void) {
        updateConfigAndSave { config in
            update(&config.providers)
        }
    }
    
    /// Get current provider setting
    func getProviderSetting(_ provider: AIProvider) -> ProviderSetting? {
        let providerName = provider.rawValue.lowercased()
        switch providerName {
        case "ollama":
            let providerConfig = config.providers.ollama
            return ProviderSetting(
                url: providerConfig.url,
                model: config.proofreading.model,
                apiKey: providerConfig.apiKey
            )
        case "openai":
            let providerConfig = config.providers.openai
            return ProviderSetting(
                url: providerConfig.url,
                model: config.proofreading.model,
                apiKey: providerConfig.apiKey
            )
        default:
            return nil
        }
    }
}
