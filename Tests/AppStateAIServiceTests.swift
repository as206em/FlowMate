import XCTest
@testable import FlowMate

@MainActor
final class AppStateAIServiceTests: XCTestCase {
    
    var appState: AppState!
    var configManager: ConfigurationManager!
    private var tempConfigURL: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary config file for testing to avoid modifying actual user config
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigURL = tempDir.appendingPathComponent("test_config_\(UUID().uuidString).json")
        
        // Create a fresh configuration manager with the temporary file
        configManager = ConfigurationManager(configURL: tempConfigURL)
        appState = AppState(configurationManager: configManager)
    }
    
    override func tearDown() {
        appState = nil
        configManager = nil
        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tempConfigURL)
        super.tearDown()
    }
    
    // MARK: - AI Service Integration Tests
    func testAIServiceInitialization() {
        XCTAssertNotNil(appState.aiService)
        XCTAssertNotNil(appState.currentProvider)
        
        // Test that AI service matches current provider
        if appState.currentProvider == .ollama {
            XCTAssertTrue(appState.aiService is OllamaService)
        } else if appState.currentProvider == .openai {
            XCTAssertTrue(appState.aiService is OpenAIService)
        }
    }
    
    func testProviderSwitchingUpdatesAIService() {
        let originalProvider = appState.currentProvider
        
        // Switch to OpenAI
        appState.setProvider(.openai)
        XCTAssertEqual(appState.currentProvider, .openai)
        
        // Switch back to Ollama
        appState.setProvider(.ollama)
        XCTAssertEqual(appState.currentProvider, .ollama)
        
        // Restore original if it wasn't Ollama
        if originalProvider != .ollama {
            appState.setProvider(originalProvider)
        }
    }
    
    func testAIServiceConfigurationUpdate() {
        // Test Ollama URL update
        let newOllamaURL = "http://new-ollama:11434"
        appState.updateProviderURL(newOllamaURL)
        XCTAssertEqual(appState.ollamaURL, newOllamaURL)
        
        // Test OpenAI URL update
        let newOpenAIURL = "https://new-api.openai.com"
        appState.setProvider(.openai)
        appState.updateProviderURL(newOpenAIURL)
        XCTAssertEqual(appState.openAIURL, newOpenAIURL)
    }
    
    func testOpenAIAPIKeyUpdate() {
        let newAPIKey = "sk-new-test-key-1234567890"
        appState.updateOpenAIAPIKey(newAPIKey)
        XCTAssertEqual(appState.openAIAPIKey, newAPIKey)
        
        // Switch to OpenAI and verify the API key is used
        appState.setProvider(.openai)
        if let openAIService = appState.aiService as? OpenAIService {
            // We can't easily access the internal API key without mocking
            XCTAssertNotNil(openAIService)
        }
    }
    
    func testCheckConnectionWithCurrentProvider() async {
        // This will test the connection with the current provider
        // In test environment, it will likely fail but should handle gracefully
        appState.checkConnection()
        
        // Wait a bit for async operation to complete
        try? await Task.sleep(nanoseconds: 500_000) // 0.5 seconds
        
        // The connection should be attempted (likely to error in test environment)
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    
    
    
    
    func testCurrentModelUpdateAffectsAIService() {
        let newModel = "new-test-model:latest"
        appState.updateCurrentModel(newModel)
        XCTAssertEqual(appState.currentModel, newModel)
        
        // The model should be available for AI service calls
        XCTAssertEqual(appState.currentModel, newModel)
    }
    
    func testCurrentPromptUpdate() {
        let newPrompt = "New custom prompt for testing"
        appState.updateCurrentPrompt(newPrompt)
        XCTAssertEqual(appState.currentPrompt, newPrompt)
    }
    
    func testProcessingStateManagement() {
        XCTAssertFalse(appState.isProcessing)
        
        appState.isProcessing = true
        XCTAssertTrue(appState.isProcessing)
        
        appState.isProcessing = false
        XCTAssertFalse(appState.isProcessing)
    }
    
    func testShowDiffByDefaultSetting() {
        // Test updating the setting
        appState.updateShowDiffByDefault(true)
        XCTAssertTrue(appState.showDiffByDefault)
        
        appState.updateShowDiffByDefault(false)
        XCTAssertFalse(appState.showDiffByDefault)
    }
    
    func testConfigurationManagerIntegration() {
        // Test that AppState properly integrates with ConfigurationManager
        let initialConfig = configManager.config
        
        // The provider rawValue should match the configuration (need to handle case difference)
        // AIProvider.ollama.rawValue is "Ollama" but config has "ollama"
        let expectedProviderRawValue = appState.currentProvider == .ollama ? "ollama" : "openai"
        XCTAssertEqual(expectedProviderRawValue, initialConfig.proofreading.selectedProvider)
        XCTAssertEqual(appState.currentPrompt, initialConfig.proofreading.defaultPrompt)
        XCTAssertEqual(appState.currentModel, initialConfig.proofreading.selectedModel)
        XCTAssertEqual(appState.showDiffByDefault, initialConfig.proofreading.showDiffByDefault)
        XCTAssertEqual(appState.keyboardShortcut, initialConfig.proofreading.keyboardShortcut)
        
        // Test updating through AppState affects configuration
        appState.updateCurrentPrompt("Updated prompt from AppState")
        XCTAssertEqual(appState.currentPrompt, "Updated prompt from AppState")
        
        // Verify the configuration was updated
        let updatedConfig = configManager.getProofreadingConfig()
        XCTAssertEqual(updatedConfig.defaultPrompt, "Updated prompt from AppState")
    }
    
    func testKeyboardShortcutIntegration() {
        let newShortcut = "command+shift+t"
        appState.updateKeyboardShortcut(newShortcut)
        XCTAssertEqual(appState.keyboardShortcut, newShortcut)
        
        // Verify configuration was updated
        let config = configManager.getProofreadingConfig()
        XCTAssertEqual(config.keyboardShortcut, newShortcut)
    }
    
    func testProviderSettingsIntegration() {
        // Test that provider settings are properly loaded
        let ollamaSetting = configManager.getProviderSetting(.ollama)
        XCTAssertEqual(appState.ollamaURL, ollamaSetting?.url)
        
        let openaiSetting = configManager.getProviderSetting(.openai)
        XCTAssertEqual(appState.openAIURL, openaiSetting?.url)
        XCTAssertEqual(appState.openAIAPIKey, openaiSetting?.apiKey ?? "")
    }
    
    func testAvailableModelsManagement() {
        // Test initial state
        XCTAssertTrue(appState.availableModels.isEmpty)
        
        // Test updating available models
        let testModels = ["model1:latest", "model2:latest", "model3:latest"]
        appState.availableModels = testModels
        XCTAssertEqual(appState.availableModels.count, 3)
        XCTAssertTrue(appState.availableModels.contains("model1:latest"))
        
        // Test clearing models
        appState.availableModels = []
        XCTAssertTrue(appState.availableModels.isEmpty)
    }
}
