import XCTest
import AppKit
@testable import FlowMate

final class KeyboardShortcutParsingTests: XCTestCase {

    func testValidShortcutsParse() {
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut("command+.")?.0, 47)
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut("command+.")?.1, [.command])
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut("ctrl+shift+p")?.1, [.control, .shift])
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut("ctrl+alt+delete")?.1, [.control, .option])
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut("Command + Period")?.0, 47)
        XCTAssertNotNil(KeyboardShortcutManager.parseShortcut("option+space"))
        // Function keys may be used without a modifier
        XCTAssertNotNil(KeyboardShortcutManager.parseShortcut("f5"))
    }

    func testInvalidShortcutsAreRejected() {
        // These used to fall back to the plain "A" key, firing on normal typing
        XCTAssertNil(KeyboardShortcutManager.parseShortcut(""))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("command"))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("control+shift"))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("command+home"))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("command+plus"))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("p"))
        XCTAssertNil(KeyboardShortcutManager.parseShortcut("command+a+b"))
    }

    @MainActor
    func testInvalidShortcutIsNotSaved() {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("shortcut-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let configManager = ConfigurationManager(configURL: configURL)
        let appState = AppState(configurationManager: configManager, statusManager: StatusManager())

        appState.updateKeyboardShortcut("command+shift+p")
        XCTAssertNil(appState.shortcutError)
        XCTAssertEqual(configManager.getProofreadingConfig().keyboardShortcut, "command+shift+p")

        appState.updateKeyboardShortcut("command+nonsense")
        XCTAssertNotNil(appState.shortcutError)
        XCTAssertEqual(configManager.getProofreadingConfig().keyboardShortcut, "command+shift+p")
    }

    @MainActor
    func testProviderSettingsSaveToTheRightProvider() {
        let configURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("provider-test-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: configURL) }
        let configManager = ConfigurationManager(configURL: configURL)
        let appState = AppState(configurationManager: configManager, statusManager: StatusManager())
        appState.setProvider(.ollama)

        // Configuring OpenAI while Ollama is active must not touch the Ollama URL
        appState.updateProviderSettings(
            ollamaURL: "http://127.0.0.1:11434",
            openAIURL: " https://api.openai.com ",
            openAIAPIKey: "sk-test"
        )
        let providers = configManager.config.providers
        XCTAssertEqual(providers.ollama.url, "http://127.0.0.1:11434")
        XCTAssertEqual(providers.openai.url, "https://api.openai.com")
        XCTAssertEqual(providers.openai.apiKey, "sk-test")
    }

    func testInvalidOpenAIURLThrowsInsteadOfCrashing() async {
        let service = OpenAIService(baseURL: "not a url", apiKey: "sk-test")
        do {
            _ = try await service.listModels()
            XCTFail("Expected an error for an invalid URL")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid OpenAI URL"))
        }
        do {
            _ = try await service.generate(model: "gpt-4o", prompt: "hi")
            XCTFail("Expected an error for an invalid URL")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Invalid OpenAI URL"))
        }
    }

    func testChatRequestOmitsTemperatureWhenNil() throws {
        let body = OpenAIChatCompletionRequest(model: "m", messages: [.init(role: "user", content: "x")], temperature: nil)
        let json = String(data: try JSONEncoder().encode(body), encoding: .utf8) ?? ""
        XCTAssertFalse(json.contains("temperature"))
        XCTAssertFalse(json.contains("max_tokens"))
    }
}
