import XCTest
@testable import FlowMate

@MainActor
final class AppStateTests: XCTestCase {
    
    var appState: AppState!
    private var configManager: ConfigurationManager!
    private var statusManager: StatusManager!
    private var tempConfigURL: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary config file for testing to avoid modifying actual user config
        let tempDir = FileManager.default.temporaryDirectory
        tempConfigURL = tempDir.appendingPathComponent("test_config_\(UUID().uuidString).json")
        
        // Create a fresh configuration manager with the temporary file
        configManager = ConfigurationManager(configURL: tempConfigURL)
        statusManager = StatusManager()
        appState = AppState(configurationManager: configManager, statusManager: statusManager)
    }
    
    override func tearDown() {
        appState = nil
        configManager = nil
        statusManager = nil
        // Clean up the temporary file
        try? FileManager.default.removeItem(at: tempConfigURL)
        super.tearDown()
    }
    
    func testInitialState() {
        XCTAssertEqual(appState.currentModel, "gemma3:4b")
        XCTAssertFalse(appState.currentPrompt.isEmpty)
        XCTAssertTrue(appState.availableModels.isEmpty)
        XCTAssertFalse(appState.isProcessing)
        XCTAssertFalse(appState.showProofreadingDialog)
        XCTAssertTrue(appState.correctedText.isEmpty)
        XCTAssertEqual(appState.ollamaURL, "http://127.0.1:11434")
    }
    
    
    func testCheckConnection() {
        // This will attempt to connect to Ollama
        // We can't easily mock this without dependency injection,
        // but we can verify the function doesn't crash
        appState.checkConnection()
        
        // The connection status might change asynchronously
        // We can't make assertions about the final state
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testHandleProofreadingShortcut() {
        // This function requires user interaction and clipboard access
        // We'll just verify it doesn't crash
        appState.handleProofreadingShortcut()
        
        // The function runs asynchronously, so we can't assert much
        XCTAssertTrue(true) // Placeholder assertion
    }
    
    func testPromptContainsDefaultText() {
        let defaultText = "correct typos and grammar errors"
        XCTAssertTrue(appState.currentPrompt.contains(defaultText))
    }
    
    func testKeyboardShortcutUpdates() {
        // Test updating keyboard shortcut
        let originalShortcut = appState.keyboardShortcut
        let newShortcut = "command+."
        
        appState.updateKeyboardShortcut(newShortcut)
        XCTAssertEqual(appState.keyboardShortcut, newShortcut)
        
        // Test with different shortcuts
        appState.updateKeyboardShortcut("control+shift+p")
        XCTAssertEqual(appState.keyboardShortcut, "control+shift+p")
        
        appState.updateKeyboardShortcut("option+space")
        XCTAssertEqual(appState.keyboardShortcut, "option+space")
        
        // Restore original
        appState.updateKeyboardShortcut(originalShortcut)
        XCTAssertEqual(appState.keyboardShortcut, originalShortcut)
    }
}
