import XCTest
import AppKit
@testable import FlowMate

final class ReviewFixesTests: XCTestCase {

    // MARK: - Retry rules

    func testOnlyTransientErrorsAreRetried() {
        XCTAssertTrue(ProofreadingService.isRetryable(URLError(.timedOut)))
        XCTAssertTrue(ProofreadingService.isRetryable(URLError(.cannotConnectToHost)))
        XCTAssertTrue(ProofreadingService.isRetryable(NSError(domain: "OpenAIService", code: 429)))
        XCTAssertTrue(ProofreadingService.isRetryable(NSError(domain: "OllamaService", code: 503)))

        XCTAssertFalse(ProofreadingService.isRetryable(NSError(domain: "OpenAIService", code: 401)))
        XCTAssertFalse(ProofreadingService.isRetryable(NSError(domain: "OllamaService", code: 404)))
        XCTAssertFalse(ProofreadingService.isRetryable(NSError(domain: "OpenAIService", code: -2))) // invalid URL
        XCTAssertFalse(ProofreadingService.isRetryable(NSError(domain: "OpenAIService", code: -4))) // cut off
        XCTAssertFalse(ProofreadingService.isRetryable(CancellationError()))
    }

    private final class FailingService: AIService {
        let error: Error
        private(set) var calls = 0
        init(error: Error) { self.error = error }
        func listModels() async throws -> [String] { [] }
        func generate(model: String, prompt: String) async throws -> String {
            calls += 1
            throw error
        }
    }

    func testPermanentErrorIsNotRetried() async {
        let service = FailingService(error: NSError(domain: "OllamaService", code: 404,
                                                    userInfo: [NSLocalizedDescriptionKey: "Ollama: model 'x' not found"]))
        let result = await ProofreadingService().proofread(text: "hi", model: "x", prompt: "p",
                                                          aiService: service, promptBuilder: PromptBuilder(), maxRetries: 3)
        XCTAssertEqual(service.calls, 1)
        guard case .failure(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertEqual(error.localizedDescription, "Ollama: model 'x' not found")
    }

    func testCancelledRunStopsRetrying() async {
        let service = FailingService(error: URLError(.timedOut))
        let task = Task {
            await ProofreadingService().proofread(text: "hi", model: "x", prompt: "p",
                                                  aiService: service, promptBuilder: PromptBuilder(), maxRetries: 3)
        }
        try? await Task.sleep(nanoseconds: 200_000_000) // first attempt fails, now waiting to retry
        task.cancel()
        let result = await task.value
        XCTAssertEqual(service.calls, 1)
        guard case .failure(let error) = result else { return XCTFail("Expected failure") }
        XCTAssertTrue(error is CancellationError)
    }

    // MARK: - Clipboard snapshot

    func testPasteboardSnapshotRestoresAllTypes() {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("FlowMateTest-\(UUID().uuidString)"))
        defer { pasteboard.releaseGlobally() }

        let item = NSPasteboardItem()
        let imageData = Data([0x89, 0x50, 0x4E, 0x47, 0x01, 0x02])
        item.setData(imageData, forType: .png)
        item.setString("<b>rich</b>", forType: .html)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])

        let snapshot = pasteboard.snapshot()
        pasteboard.clearContents()
        pasteboard.setString("selected text", forType: .string)

        pasteboard.restore(snapshot)
        XCTAssertEqual(pasteboard.data(forType: .png), imageData)
        XCTAssertEqual(pasteboard.string(forType: .html), "<b>rich</b>")
        XCTAssertNil(pasteboard.string(forType: .string))
    }

    // MARK: - Keychain failure

    @MainActor
    func testKeyStaysInFileWhenSecretStoreFails() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keyfail-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let store = InMemorySecretStore()
        store.failsWrites = true

        let manager = ConfigurationManager(configURL: url, secretStore: store)
        manager.updateProvidersConfig { $0.openai.apiKey = "sk-keep-me" }
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("sk-keep-me"))

        // Once the store works again, the next save moves the key out of the file
        store.failsWrites = false
        manager.saveConfiguration()
        XCTAssertFalse(try String(contentsOf: url, encoding: .utf8).contains("sk-keep-me"))
        XCTAssertEqual(store.secret(for: "openai-api-key"), "sk-keep-me")
    }

    // MARK: - Defaults

    func testDefaultURLsComeFromOnePlace() {
        XCTAssertEqual(AIConfiguration.default.ollamaURL, AIProvider.ollama.defaultURL)
        XCTAssertEqual(AIConfiguration.default.openAIURL, AIProvider.openai.defaultURL)
    }
}

final class ShortcutRecordingTests: XCTestCase {
    func testRecordedKeysBecomeShortcutStrings() {
        XCTAssertEqual(KeyboardShortcutManager.shortcutString(keyCode: 47, modifiers: [.command]), "command+.")
        XCTAssertEqual(KeyboardShortcutManager.shortcutString(keyCode: 35, modifiers: [.command, .shift]), "shift+command+p")
        XCTAssertEqual(KeyboardShortcutManager.shortcutString(keyCode: 49, modifiers: [.option]), "option+space")
        XCTAssertEqual(KeyboardShortcutManager.shortcutString(keyCode: 96, modifiers: []), "f5")
        // A plain letter would fire while typing, so it's rejected
        XCTAssertNil(KeyboardShortcutManager.shortcutString(keyCode: 0, modifiers: []))
        // Recorded strings round-trip through the parser
        let recorded = KeyboardShortcutManager.shortcutString(keyCode: 35, modifiers: [.command, .shift])!
        XCTAssertEqual(KeyboardShortcutManager.parseShortcut(recorded)?.0, 35)
    }
}
