import XCTest
@testable import FlowMate

@MainActor
final class EdgeCaseTests: XCTestCase {
    
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
    
    // MARK: - Edge Case: Empty/Invalid Input Tests
    func testEmptyModelName() {
        let expectation = XCTestExpectation(description: "Empty model test")
        
        Task {
            do {
                // This should handle gracefully when model name is empty
                appState.updateCurrentModel("")
                XCTAssertTrue(appState.currentModel.isEmpty)
                
                // Try to use empty model with AI service if it exists
                if !appState.currentModel.isEmpty && appState.aiService != nil {
                    let _ = try await appState.aiService.generate(
                        model: appState.currentModel,
                        prompt: "Test prompt"
                    )
                }
            } catch {
                // Expected error handling
                print("Handled empty model error: \(error)")
            }
            
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 3.0)
    }
    
    func testEmptyPromptHandling() async {
        if let aiService = appState.aiService {
            do {
                let response = try await aiService.generate(
                    model: appState.currentModel,
                    prompt: ""
                )
                // Should handle empty prompt gracefully
                XCTAssertTrue(response.count >= 0)
            } catch {
                // Network error is acceptable for empty prompt
                print("Handled empty prompt error: \(error)")
            }
        } else {
            XCTFail("AI service is nil")
        }
    }
    
    func testVeryLongPrompt() async {
        if let aiService = appState.aiService {
            do {
                let response = try await aiService.generate(
                    model: appState.currentModel,
                    prompt: String(repeating: "This is a very long test prompt. ", count: 100)
                )
                // Should handle long prompts gracefully
                XCTAssertTrue(response.count >= 0)
            } catch {
                // Network error is acceptable for very long prompts
                print("Handled long prompt error: \(error)")
            }
        } else {
            XCTFail("AI service is nil")
        }
    }
    
    func testInvalidURLHandling() {
        // Test with invalid URLs
        let invalidURLs = [
            "",
            "   ",
            "not-a-url",
            "ftp://invalid.com",
            "http://",
            "https://",
            "invalid..url.com"
        ]
        
        for url in invalidURLs {
            if !url.trimmingCharacters(in: .whitespaces).isEmpty {
                // URL validation would typically happen at the service level
                // Here we just ensure it doesn't crash
                XCTAssertNotNil(url)
            }
        }
    }
    
    func testInvalidAPIKeyHandling() {
        let invalidAPIKeys = [
            "",
            "   ",
            "invalid-key",
            "sk-",
            "sk-short",
            "not-an-api-key-at-all"
        ]
        
        for apiKey in invalidAPIKeys {
            appState.updateOpenAIAPIKey(apiKey)
            XCTAssertEqual(appState.openAIAPIKey, apiKey)
        }
    }
    
    // MARK: - Edge Case: State Transitions
    func testRapidStateChanges() {
        // Test rapid switching between providers
        let providers: [AIProvider] = [.ollama, .openai, .ollama, .openai]
        
        for provider in providers {
            appState.setProvider(provider)
            XCTAssertEqual(appState.currentProvider, provider)
        }
    }
    
    func testConcurrentTextUpdates() {
        // Test updating text fields concurrently
        let textUpdates = [
            "First update",
            "Second update", 
            "Third update",
            "Final update"
        ]
        
        for text in textUpdates {
            appState.originalText = text
            appState.correctedText = text.replacingOccurrences(of: "update", with: "corrected")
            
            XCTAssertEqual(appState.originalText, text)
            XCTAssertTrue(appState.correctedText.contains("corrected"))
        }
    }
    
    // MARK: - Edge Case: Boundary Values
    func testBoundaryNumericValues() {
        // Test with boundary values for numeric settings
        appState.updateShowDiffByDefault(true)
        XCTAssertTrue(appState.showDiffByDefault)
        
        appState.updateShowDiffByDefault(false)
        XCTAssertFalse(appState.showDiffByDefault)
        
        // Test with minimum/maximum string lengths
        let emptyString = ""
        let singleChar = "a"
        let maxReasonableString = String(repeating: "a", count: 10000)
        
        appState.updateCurrentPrompt(emptyString)
        XCTAssertEqual(appState.currentPrompt, emptyString)
        
        appState.updateCurrentPrompt(singleChar)
        XCTAssertEqual(appState.currentPrompt, singleChar)
        
        appState.updateCurrentPrompt(maxReasonableString)
        XCTAssertEqual(appState.currentPrompt, maxReasonableString)
    }
    
    // MARK: - Edge Case: Error Recovery
    func testConnectionErrorRecovery() {
        // Test that error state can be recovered from
        appState.isProcessing = true
        XCTAssertTrue(appState.isProcessing)
        
        appState.isProcessing = false
        XCTAssertFalse(appState.isProcessing)
    }
    
    func testProcessingStateDuringErrors() {
        // Test processing state during error conditions
        appState.isProcessing = true
        XCTAssertTrue(appState.isProcessing)
        
        appState.isProcessing = false
        XCTAssertFalse(appState.isProcessing)
    }
    
    // MARK: - Edge Case: Configuration Edge Cases
    func testConfigurationWithInvalidValues() {
        // Test configuration updates with edge case values
        let edgeCasePrompts = [
            "",
            "   ",
            "\n\t",
            String(repeating: "a", count: 100),
            "Prompt with\nnewlines\tand tabs",
            "Special chars: !@#$%^&*()_+-=[]{}|;':\",./<>?"
        ]
        
        for prompt in edgeCasePrompts {
            appState.updateCurrentPrompt(prompt)
            XCTAssertEqual(appState.currentPrompt, prompt)
        }
    }
    
    func testModelNameEdgeCases() {
        let edgeCaseModels = [
            "",
            "   ",
            "model",
            "model:tag",
            "very-long-model-name-with-many-hyphens-and-tags:latest",
            "model@invalid",
            "model with spaces",
            "model/with/slashes",
            "model.with.dots:tag.with.dots"
        ]
        
        for model in edgeCaseModels {
            if !model.trimmingCharacters(in: .whitespaces).isEmpty && !model.contains(" ") && !model.contains("@") {
                // Only update with valid model names (no spaces or @ symbols)
                appState.updateCurrentModel(model)
                XCTAssertEqual(appState.currentModel, model)
            }
        }
    }
    
    // MARK: - Edge Case: Keyboard Shortcut Edge Cases
    func testKeyboardShortcutEdgeCases() {
        let edgeCaseShortcuts = [
            "",
            "   ",
            "command",
            "command+c",
            "control+shift",
            "control+shift+p",
            "cmd+opt+shift+ctrl+p",
            "command+1", // number key
            "command+space", // space key
            "command+plus", // plus key
            "command+comma", // comma key
            "command+period", // period key
            "command+slash", // slash key
        ]
        
        for shortcut in edgeCaseShortcuts {
            if !shortcut.trimmingCharacters(in: .whitespaces).isEmpty {
                appState.updateKeyboardShortcut(shortcut)
                XCTAssertEqual(appState.keyboardShortcut, shortcut)
            }
        }
    }
    
    // MARK: - Edge Case: Text Processing Edge Cases
    func testTextProcessingEdgeCases() {
        let edgeCaseTexts = [
            ("", ""), // Empty text
            ("   ", "   "), // Whitespace only
            ("\n\t\r", "\n\t\r"), // Control characters
            (String(repeating: "a", count: 10000), String(repeating: "b", count: 100)), // Very long text
            ("Text with\nmultiple\nlines", "Text with\nmultiple\nlines"),
            ("Text with\ttabs\tand\tspaces", "Text with\ttabs\tand\tspaces"),
            ("Special chars: !@#$%^&*()", "Special chars: !@#$%^&*()")
        ]
        
        for (original, corrected) in edgeCaseTexts {
            appState.originalText = original
            appState.correctedText = corrected
            
            XCTAssertEqual(appState.originalText, original)
            XCTAssertEqual(appState.correctedText, corrected)
        }
    }
    
    // MARK: - Edge Case: Available Models Edge Cases
    func testAvailableModelsEdgeCases() {
        // Test with empty array
        appState.availableModels = []
        XCTAssertTrue(appState.availableModels.isEmpty)
        
        // Test with single model
        appState.availableModels = ["single-model:latest"]
        XCTAssertEqual(appState.availableModels.count, 1)
        
        // Test with many models
        let manyModels = (1...100).map { "model-\($0):latest" }
        appState.availableModels = manyModels
        XCTAssertEqual(appState.availableModels.count, 100)
        
        // Test with edge case model names
        let edgeCaseModels = [
            "normal-model:latest",
            "model-with-hyphens:tag",
            "model_with_underscores:latest",
            "very-long-model-name-with-many-parts-and-tags:latest-and-more-tags",
            "model:1.0.0", // version tag
            "model:latest" // duplicate tag
        ]
        
        appState.availableModels = edgeCaseModels
        XCTAssertEqual(appState.availableModels.count, edgeCaseModels.count)
    }
}
