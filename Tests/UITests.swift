import XCTest
@testable import FlowMate

@MainActor
final class UITests: XCTestCase {
    
    var appState: AppState!
    private var configManager: ConfigurationManager!
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
    
    // MARK: - StatusMenuView Tests
    func testStatusMenuViewInitialState() {
        let statusMenuView = StatusMenuView()
        // Since we can't easily test SwiftUI views directly without UI testing,
        // we'll test the underlying state that drives the view
        
        // Note: showProofreadingDialog and showSettings are methods, not properties
        // We can't easily test these boolean states directly
        
        // Test status section data
        XCTAssertFalse(appState.currentModel.isEmpty)
        XCTAssertFalse(appState.currentPrompt.isEmpty)
        
        // Test connection status
        XCTAssertEqual(appState.connectionStatus, .disconnected)
    }
    
    func testStatusMenuViewStatusText() {
        // Test different status states
        appState.connectionStatus = .connected
        XCTAssertEqual(appState.connectionStatus, .connected)
        
        appState.connectionStatus = .disconnected
        XCTAssertEqual(appState.connectionStatus, .disconnected)
        
        appState.connectionStatus = .error
        XCTAssertEqual(appState.connectionStatus, .error)
    }
    
    func testStatusMenuViewStatusColor() {
        // Test status colors based on connection status
        appState.connectionStatus = .connected
        // The color would be determined by the view, but we can test the status logic
        XCTAssertTrue(appState.connectionStatus == .connected)
        
        appState.connectionStatus = .error
        XCTAssertTrue(appState.connectionStatus == .error)
    }
    
    // MARK: - SettingsView Tests (indirect)
    func testSettingsViewRelatedFunctionality() {
        // Test keyboard shortcut functionality
        let originalShortcut = appState.keyboardShortcut
        appState.updateKeyboardShortcut("command+shift+p")
        XCTAssertEqual(appState.keyboardShortcut, "command+shift+p")
        
        // Test current model updates
        appState.updateCurrentModel("new-model:latest")
        XCTAssertEqual(appState.currentModel, "new-model:latest")
        
        // Test current prompt updates
        appState.updateCurrentPrompt("New test prompt")
        XCTAssertEqual(appState.currentPrompt, "New test prompt")
        
        // Test show diff by default
        appState.updateShowDiffByDefault(true)
        XCTAssertTrue(appState.showDiffByDefault)
        
        appState.updateShowDiffByDefault(false)
        XCTAssertFalse(appState.showDiffByDefault)
        
        // Restore original
        appState.updateKeyboardShortcut(originalShortcut)
    }
    
    // MARK: - ProofreadingDialog Tests (indirect)
    func testProofreadingDialogStateManagement() {
        // Test proofreading dialog state
        XCTAssertFalse(appState.showProofreadingDialog)
        
        // Simulate showing proofreading dialog
        appState.showProofreadingDialog(nil)
        // Note: This will actually try to show a window, but the state should be manageable
        
        // Test text storage
        appState.originalText = "Original test text"
        appState.correctedText = "Corrected test text"
        
        XCTAssertEqual(appState.originalText, "Original test text")
        XCTAssertEqual(appState.correctedText, "Corrected test text")
        
        // Test processing state
        appState.isProcessing = true
        XCTAssertTrue(appState.isProcessing)
        
        appState.isProcessing = false
        XCTAssertFalse(appState.isProcessing)
    }
    
    // MARK: - Provider Tests
    func testProviderSwitching() {
        let originalProvider = appState.currentProvider
        
        // Test switching to OpenAI
        appState.setProvider(.openai)
        XCTAssertEqual(appState.currentProvider, .openai)
        
        // Test switching back to Ollama
        appState.setProvider(.ollama)
        XCTAssertEqual(appState.currentProvider, .ollama)
        
        // Test provider URL updates
        appState.updateProviderURL("http://new-ollama:11434")
        XCTAssertEqual(appState.ollamaURL, "http://new-ollama:11434")
        
        // Restore original
        appState.setProvider(originalProvider)
    }
    
    // MARK: - API Key Tests
    func testAPIKeyManagement() {
        // Test OpenAI API key updates
        appState.updateOpenAIAPIKey("test-api-key-123")
        XCTAssertEqual(appState.openAIAPIKey, "test-api-key-123")
        
        // Test empty API key
        appState.updateOpenAIAPIKey("")
        XCTAssertTrue(appState.openAIAPIKey.isEmpty)
    }
    
    // MARK: - Model Selection Tests
    func testModelSelection() {
        // Test model updates
        appState.updateCurrentModel("gpt-4-test")
        XCTAssertEqual(appState.currentModel, "gpt-4-test")
        
        appState.updateCurrentModel("llama2-test")
        XCTAssertEqual(appState.currentModel, "llama2-test")
        
        // Test available models management
        appState.availableModels = ["model1", "model2", "model3"]
        XCTAssertEqual(appState.availableModels.count, 3)
        XCTAssertTrue(appState.availableModels.contains("model1"))
    }
    
    // MARK: - Connection Tests
    func testConnectionFunctionality() {
        // Test connection status changes
        appState.connectionStatus = .connected
        XCTAssertEqual(appState.connectionStatus, .connected)
        
        appState.connectionStatus = .disconnected
        XCTAssertEqual(appState.connectionStatus, .disconnected)
        
        appState.connectionStatus = .error
        XCTAssertEqual(appState.connectionStatus, .error)
        
        // Test status icon changes based on connection status
        appState.connectionStatus = .connected
        appState.isProcessing = false
        XCTAssertEqual(appState.statusIcon, "checkmark.circle")
        
        appState.isProcessing = true
        XCTAssertEqual(appState.statusIcon, "hourglass")
        
        appState.connectionStatus = .error
        XCTAssertEqual(appState.statusIcon, "exclamationmark.triangle")
    }
    
    // MARK: - Keyboard Shortcut Tests
    func testKeyboardShortcutParsing() {
        // Test various keyboard shortcut formats
        let shortcuts = [
            "command+c",
            "control+shift+p", 
            "option+space",
            "cmd+shift+.",
            "ctrl+alt+delete"
        ]
        
        for shortcut in shortcuts {
            appState.updateKeyboardShortcut(shortcut)
            XCTAssertEqual(appState.keyboardShortcut, shortcut)
        }
    }
    
    // MARK: - Text Processing Tests
    func testTextProcessingState() {
        // Test original and corrected text handling
        let originalText = "This is a test with some errors."
        let correctedText = "This is a test with corrected errors."
        
        appState.originalText = originalText
        appState.correctedText = correctedText
        
        XCTAssertEqual(appState.originalText, originalText)
        XCTAssertEqual(appState.correctedText, correctedText)
        
        // Test text clearing
        appState.originalText = ""
        appState.correctedText = ""
        
        XCTAssertTrue(appState.originalText.isEmpty)
        XCTAssertTrue(appState.correctedText.isEmpty)
    }
    
    // MARK: - Configuration Persistence Tests
    func testConfigurationState() {
        // Test that configuration changes are properly reflected in app state
        let initialConfig = configManager.config
        
        // Verify initial state matches configuration (handle case difference)
        // AIProvider.ollama.rawValue is "Ollama" but config has "ollama"
        let expectedProviderRawValue = appState.currentProvider == .ollama ? "ollama" : "openai"
        XCTAssertEqual(expectedProviderRawValue, initialConfig.proofreading.selectedProvider)
        XCTAssertEqual(appState.currentPrompt, initialConfig.proofreading.defaultPrompt)
        XCTAssertEqual(appState.currentModel, initialConfig.proofreading.model)
        XCTAssertEqual(appState.showDiffByDefault, initialConfig.proofreading.showDiffByDefault)
        XCTAssertEqual(appState.keyboardShortcut, initialConfig.proofreading.keyboardShortcut)
    }
}
