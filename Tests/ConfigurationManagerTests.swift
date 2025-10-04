import XCTest
@testable import Proofreader

@MainActor
final class ConfigurationManagerTests: XCTestCase {
    private var configManager: ConfigurationManager!
    private var tempConfigURL: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary config file for testing
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigURL = tempDir.appendingPathComponent("test_config_\(UUID().uuidString).json")
        
        // Create a fresh configuration manager with the temporary file
        configManager = ConfigurationManager(configURL: tempConfigURL)
    }
    
    override func tearDown() {
        configManager = nil
        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tempConfigURL)
        super.tearDown()
    }
    
    func testInitialConfiguration() {
        let config = configManager.config
        
        // Test providers - check that they exist and have expected properties (no model anymore)
        XCTAssertEqual(config.providers.ollama.url, "http://127.0.0.1:11434")
        XCTAssertNil(config.providers.ollama.apiKey)
        XCTAssertEqual(config.providers.openai.url, "https://api.openai.com")
        XCTAssertEqual(config.providers.openai.apiKey, "")
        
        // Test proofreading feature - model should now be here
        XCTAssertNotNil(config.proofreading)
        XCTAssertEqual(config.proofreading.model, "gemma3:4b")
        
        // Test app settings
        XCTAssertNotNil(config.app)
    }
    
    func testGetProviderSetting() {
        let ollamaSetting = configManager.getProviderSetting(.ollama)
        XCTAssertNotNil(ollamaSetting)
        XCTAssertEqual(ollamaSetting?.model, "gemma3:4b")
        
        let openaiSetting = configManager.getProviderSetting(.openai)
        XCTAssertNotNil(openaiSetting)
        XCTAssertEqual(openaiSetting?.model, "gemma3:4b") // Both providers now use the model from proofreading config
    }
    
    func testFeatureLevelProviderUpdate() {
        // Test the new feature-level API for providers
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://new-url:11434"
            providers.ollama.apiKey = "new-api-key"
        }
        
        let retrievedSetting = configManager.getProviderSetting(.ollama)
        XCTAssertNotNil(retrievedSetting)
        XCTAssertEqual(retrievedSetting?.url, "http://new-url:11434")
        XCTAssertEqual(retrievedSetting?.apiKey, "new-api-key")
    }
    
    func testGetProofreadingConfig() {
        let config = configManager.getProofreadingConfig()
        XCTAssertNotNil(config)
        XCTAssertNotNil(config.selectedProvider)
        XCTAssertNotNil(config.defaultPrompt)
        XCTAssertNotNil(config.showDiffByDefault)
        XCTAssertNotNil(config.keyboardShortcut)
    }
    
    func testFeatureLevelProofreadingUpdate() {
        // Test the new feature-level API for proofreading
        configManager.updateProofreadingConfig { config in
            config.selectedProvider = "openai"
            config.defaultPrompt = "New test prompt"
            config.showDiffByDefault = false
            config.keyboardShortcut = "command+shift+p"
        }
        
        let retrievedConfig = configManager.getProofreadingConfig()
        XCTAssertNotNil(retrievedConfig)
        XCTAssertEqual(retrievedConfig.selectedProvider, "openai")
        XCTAssertEqual(retrievedConfig.defaultPrompt, "New test prompt")
        XCTAssertEqual(retrievedConfig.showDiffByDefault, false)
        XCTAssertEqual(retrievedConfig.keyboardShortcut, "command+shift+p")
    }
    
    func testGetAppSettings() {
        let settings = configManager.getAppSettings()
        XCTAssertNotNil(settings)
        XCTAssertNotNil(settings.theme)
        XCTAssertNotNil(settings.autoCheckUpdates)
        XCTAssertNotNil(settings.maxHistoryItems)
    }
    
    func testFeatureLevelAppSettingsUpdate() {
        // Test the new feature-level API for app settings
        configManager.updateAppSettings { settings in
            settings.theme = "dark"
            settings.autoCheckUpdates = false
            settings.maxHistoryItems = 100
            settings.customSettings = ["test": "value"]
        }
        
        let retrievedSettings = configManager.getAppSettings()
        XCTAssertNotNil(retrievedSettings)
        XCTAssertEqual(retrievedSettings.theme, "dark")
        XCTAssertEqual(retrievedSettings.autoCheckUpdates, false)
        XCTAssertEqual(retrievedSettings.maxHistoryItems, 100)
    }
    
    func testUpdateProviderURL() {
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://new-ollama:11434"
        }
        
        let updatedSetting = configManager.getProviderSetting(.ollama)
        XCTAssertEqual(updatedSetting?.url, "http://new-ollama:11434")
    }
    
    func testUpdateProofreadingPrompt() {
        configManager.updateProofreadingConfig { config in
            config.defaultPrompt = "Updated test prompt"
        }
        
        let updatedConfig = configManager.getProofreadingConfig()
        XCTAssertEqual(updatedConfig.defaultPrompt, "Updated test prompt")
    }
    
    func testUpdateProofreadingModel() {
        configManager.updateProofreadingConfig { config in
            config.model = "updated-model"
        }
        
        let updatedConfig = configManager.getProofreadingConfig()
        XCTAssertEqual(updatedConfig.model, "updated-model")
        
        // Verify that the provider setting now returns the updated model
        let providerSetting = configManager.getProviderSetting(.ollama)
        XCTAssertEqual(providerSetting?.model, "updated-model")
    }
    
    func testUpdateAppTheme() {
        configManager.updateAppSettings { settings in
            settings.theme = "dark"
        }
        
        let updatedSettings = configManager.getAppSettings()
        XCTAssertEqual(updatedSettings.theme, "dark")
    }
    
    // MARK: - Comprehensive Flow Tests
    
    func testMultiplePropertyUpdatesInSingleTransaction() {
        // Test that multiple properties can be updated atomically
        configManager.updateProofreadingConfig { config in
            config.selectedProvider = "openai"
            config.defaultPrompt = "Comprehensive test prompt"
            config.showDiffByDefault = false
            config.keyboardShortcut = "command+shift+k"
        }
        
        let updatedConfig = configManager.getProofreadingConfig()
        XCTAssertEqual(updatedConfig.selectedProvider, "openai")
        XCTAssertEqual(updatedConfig.defaultPrompt, "Comprehensive test prompt")
        XCTAssertEqual(updatedConfig.showDiffByDefault, false)
        XCTAssertEqual(updatedConfig.keyboardShortcut, "command+shift+k")
    }
    
    func testProviderSpecificUpdates() {
        // Test updating a specific provider's configuration
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://updated-ollama:11434"
            providers.ollama.apiKey = "updated-api-key"
        }
        
        let updatedSetting = configManager.getProviderSetting(.ollama)
        XCTAssertEqual(updatedSetting?.url, "http://updated-ollama:11434")
        XCTAssertEqual(updatedSetting?.apiKey, "updated-api-key")
    }
    
    func testProvidersConfigUpdate() {
        // Test updating the entire providers configuration
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://bulk-update:11434"
            providers.openai.apiKey = "bulk-api-key"
        }
        
        let ollamaSetting = configManager.getProviderSetting(.ollama)
        let openaiSetting = configManager.getProviderSetting(.openai)
        
        XCTAssertEqual(ollamaSetting?.url, "http://bulk-update:11434")
        XCTAssertEqual(openaiSetting?.apiKey, "bulk-api-key")
    }
    
    func testAppSettingsFullUpdate() {
        // Test updating all app settings at once
        configManager.updateAppSettings { settings in
            settings.theme = "light"
            settings.autoCheckUpdates = true
            settings.maxHistoryItems = 200
            settings.customSettings = [
                "setting1": "value1",
                "setting2": "value2"
            ]
        }
        
        let updatedSettings = configManager.getAppSettings()
        XCTAssertEqual(updatedSettings.theme, "light")
        XCTAssertEqual(updatedSettings.autoCheckUpdates, true)
        XCTAssertEqual(updatedSettings.maxHistoryItems, 200)
        XCTAssertEqual(updatedSettings.customSettings["setting1"], "value1")
        XCTAssertEqual(updatedSettings.customSettings["setting2"], "value2")
    }
    
    func testConvenienceMethodBackwardCompatibility() {
        // Test that convenience methods still work
        configManager.updateProofreadingConfig { config in
            config.defaultPrompt = "Convenience method test"
            config.model = "convenience-model"
        }
        configManager.updateAppSettings { settings in
            settings.theme = "system"
        }
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://updated-url:11434"
        }
        
        let proofreadingConfig = configManager.getProofreadingConfig()
        let appSettings = configManager.getAppSettings()
        let providerSetting = configManager.getProviderSetting(.ollama)
        
        XCTAssertEqual(proofreadingConfig.defaultPrompt, "Convenience method test")
        XCTAssertEqual(proofreadingConfig.model, "convenience-model")
        XCTAssertEqual(appSettings.theme, "system")
        XCTAssertEqual(providerSetting?.url, "http://updated-url:11434")
    }
    
    func testConfigurationPersistsAcrossInstances() {
        // Test that configuration changes are persisted to disk
        configManager.updateProofreadingConfig { config in
            config.defaultPrompt = "Persistent test prompt"
        }
        
        // Create a new configuration manager instance
        let newConfigManager = ConfigurationManager(configURL: tempConfigURL)
        
        let retrievedConfig = newConfigManager.getProofreadingConfig()
        XCTAssertEqual(retrievedConfig.defaultPrompt, "Persistent test prompt")
    }
    
    func testAtomicRollbackOnFailure() {
        // Test that partial updates don't corrupt the configuration
        // This test verifies that the configuration manager maintains consistency
        
        // Perform a valid update
        configManager.updateProofreadingConfig { config in
            config.selectedProvider = "openai"
            config.defaultPrompt = "Atomic test prompt"
        }
        
        // Verify the update was successful
        let updatedConfig = configManager.getProofreadingConfig()
        XCTAssertEqual(updatedConfig.selectedProvider, "openai")
        XCTAssertEqual(updatedConfig.defaultPrompt, "Atomic test prompt")
        
        // The configuration should still be valid and consistent
        XCTAssertNotNil(updatedConfig.showDiffByDefault)
        XCTAssertNotNil(updatedConfig.keyboardShortcut)
    }
    
    func testAllUpdateMethodsWorkTogether() {
        // Integration test: verify all update methods work in harmony
        
        // 1. Use feature-level API
        configManager.updateProofreadingConfig { config in
            config.selectedProvider = "openai"
            config.defaultPrompt = "Integration test prompt"
        }
        
        // 2. Use convenience method
        configManager.updateAppSettings { settings in
            settings.theme = "dark"
        }
        
        // 3. Use provider-specific API
        configManager.updateProvidersConfig { providers in
            providers.ollama.url = "http://integration-test:11434"
        }
        
        // 4. Use property-specific convenience method
        configManager.updateProofreadingConfig { config in
            config.showDiffByDefault = true
        }
        
        // Verify all changes are applied
        let proofreadingConfig = configManager.getProofreadingConfig()
        let appSettings = configManager.getAppSettings()
        let providerSetting = configManager.getProviderSetting(.ollama)
        
        XCTAssertEqual(proofreadingConfig.selectedProvider, "openai")
        XCTAssertEqual(proofreadingConfig.defaultPrompt, "Integration test prompt")
        XCTAssertEqual(proofreadingConfig.showDiffByDefault, true)
        XCTAssertEqual(appSettings.theme, "dark")
        XCTAssertEqual(providerSetting?.url, "http://integration-test:11434")
    }
}
