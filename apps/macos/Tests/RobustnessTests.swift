import XCTest
@testable import FlowMate

final class OutputSanitizerTests: XCTestCase {

    func testRemovesThinkingBlock() {
        let raw = "<think>The user wants me to fix typos.\nLet me check.</think>\n\nThey're going home."
        XCTAssertEqual(OutputSanitizer.clean(raw, original: "Their going home."), "They're going home.")
    }

    func testRemovesUnclosedThinkingPrefix() {
        let raw = "reasoning here...</think>They're going home."
        XCTAssertEqual(OutputSanitizer.clean(raw, original: "Their going home."), "They're going home.")
    }

    func testRemovesPreambleLine() {
        let raw = "Here's the corrected text:\n\nThey're going home."
        XCTAssertEqual(OutputSanitizer.clean(raw, original: "Their going home."), "They're going home.")
        let raw2 = "Sure! Corrected version:\nThey're going home."
        XCTAssertEqual(OutputSanitizer.clean(raw2, original: "Their going home."), "They're going home.")
    }

    func testKeepsPreambleLikeLineFromOriginal() {
        let original = "Here is my plan:\n- step one"
        let raw = "Here is my plan:\n- Step one"
        XCTAssertEqual(OutputSanitizer.clean(raw, original: original), "Here is my plan:\n- Step one")
    }

    func testRemovesCodeFenceAndQuotes() {
        XCTAssertEqual(OutputSanitizer.clean("```\nThey're going home.\n```", original: "Their going home."), "They're going home.")
        XCTAssertEqual(OutputSanitizer.clean("```markdown\n# Title\n```", original: "# Titel"), "# Title")
        XCTAssertEqual(OutputSanitizer.clean("\"They're going home.\"", original: "Their going home."), "They're going home.")
        XCTAssertEqual(OutputSanitizer.clean("“Fixed text.”", original: "Fixd text."), "Fixed text.")
    }

    func testKeepsQuotesAndFencesThatWereInTheOriginal() {
        XCTAssertEqual(OutputSanitizer.clean("\"Hello,\" she said.", original: "\"Helo,\" she said."), "\"Hello,\" she said.")
        XCTAssertEqual(OutputSanitizer.clean("```\ncode\n```", original: "```\ncode\n```"), "```\ncode\n```")
        // Quotes inside the text mean the outer ones are real
        XCTAssertEqual(OutputSanitizer.clean("\"A\" and \"B\"", original: "A and B"), "\"A\" and \"B\"")
    }

    func testRemovesTrailingNote() {
        let raw = "They're going home.\n\nNote: I changed \"their\" to \"they're\"."
        XCTAssertEqual(OutputSanitizer.clean(raw, original: "Their going home."), "They're going home.")
    }

    func testPreservesEdgeWhitespaceOfSelection() {
        XCTAssertEqual(OutputSanitizer.clean("Fixed line.", original: "Fixd line.\n"), "Fixed line.\n")
        XCTAssertEqual(OutputSanitizer.clean("  Fixed.  \n", original: "  Fixd."), "  Fixed.")
    }

    func testPlainOutputIsUnchanged() {
        let text = "This is fine.\nSecond line: with a colon."
        XCTAssertEqual(OutputSanitizer.clean(text, original: "This is fine.\nSecond line: with a colon."), text)
    }
}

final class TextDiffTests: XCTestCase {

    func testWordLevelChanges() {
        let result = TextDiff.compute(original: "I has a apple.", corrected: "I have an apple.")
        XCTAssertFalse(result.isTooLarge)
        // "has" and "a" removed, "have" and "an" inserted
        XCTAssertEqual(result.removedCount, 2)
        XCTAssertEqual(result.insertedCount, 2)
        XCTAssertEqual(String(result.original.characters), "I has a apple.")
        XCTAssertEqual(String(result.corrected.characters), "I have an apple.")
    }

    func testIdenticalTextsHaveNoChanges() {
        let result = TextDiff.compute(original: "Same text 👍", corrected: "Same text 👍")
        XCTAssertEqual(result.removedCount, 0)
        XCTAssertEqual(result.insertedCount, 0)
    }

    func testEmojiAndAccentsAreNotSplit() {
        let tokens = TextDiff.tokenize("Café 👨‍👩‍👧 ok!")
        XCTAssertEqual(tokens, ["Café", " ", "👨‍👩‍👧", " ", "ok", "!"])
        let result = TextDiff.compute(original: "Hi 👨‍👩‍👧 frend", corrected: "Hi 👨‍👩‍👧 friend")
        XCTAssertEqual(String(result.corrected.characters), "Hi 👨‍👩‍👧 friend")
        XCTAssertEqual(result.insertedCount, 1)
    }

    func testVeryLongTextSkipsHighlighting() {
        let long = Array(repeating: "word", count: TextDiff.maxTokens).joined(separator: " ")
        let result = TextDiff.compute(original: long, corrected: long + " more")
        XCTAssertTrue(result.isTooLarge)
        XCTAssertEqual(String(result.corrected.characters), long + " more")
    }

    func testLongSimilarTextIsFast() {
        let words = (0..<2000).map { "word\($0)" }
        let original = words.joined(separator: " ")
        let corrected = words.enumerated().map { $0.offset % 25 == 0 ? $0.element + "x" : $0.element }.joined(separator: " ")
        let start = Date()
        _ = TextDiff.compute(original: original, corrected: corrected)
        XCTAssertLessThan(Date().timeIntervalSince(start), 1.0)
    }
}

@MainActor
final class ConfigCompatibilityTests: XCTestCase {
    private var configURL: URL!

    override func setUp() {
        super.setUp()
        configURL = FileManager.default.temporaryDirectory.appendingPathComponent("compat-\(UUID().uuidString).json")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: configURL)
        try? FileManager.default.removeItem(at: configURL.appendingPathExtension("bak"))
        super.tearDown()
    }

    func testOldConfigMissingFieldsKeepsUserValues() throws {
        // An older config without showDialog and without the app section
        let old = """
        {
          "providers": {
            "ollama": { "url": "http://10.0.0.5:11434" },
            "openai": { "url": "https://api.openai.com" }
          },
          "proofreading": {
            "selectedProvider": "Ollama",
            "selectedModel": "llama3",
            "defaultPrompt": "My custom prompt",
            "showDiffByDefault": false,
            "keyboardShortcut": "command+shift+k"
          }
        }
        """
        try old.write(to: configURL, atomically: true, encoding: .utf8)

        let manager = ConfigurationManager(configURL: configURL)
        let config = manager.config
        XCTAssertEqual(config.providers.ollama.url, "http://10.0.0.5:11434")
        XCTAssertEqual(config.proofreading.selectedModel, "llama3")
        XCTAssertEqual(config.proofreading.defaultPrompt, "My custom prompt")
        XCTAssertEqual(config.proofreading.keyboardShortcut, "command+shift+k")
        XCTAssertFalse(config.proofreading.showDiffByDefault)
        XCTAssertTrue(config.proofreading.showDialog) // default filled in
        XCTAssertEqual(config.app.maxHistoryItems, 50) // default filled in
    }

    func testUnreadableConfigIsBackedUp() throws {
        try "{ not json".write(to: configURL, atomically: true, encoding: .utf8)
        let manager = ConfigurationManager(configURL: configURL)
        XCTAssertEqual(manager.config.proofreading.keyboardShortcut, "command+.")
        let backup = try String(contentsOf: configURL.appendingPathExtension("bak"), encoding: .utf8)
        XCTAssertEqual(backup, "{ not json")
    }

    func testMergeKeepsDefaultForWrongType() {
        let merged = ConfigurationManager.mergeJSON(
            defaults: ["a": "text", "b": ["c": 1]],
            overrides: ["a": 5, "b": ["c": 2], "extra": true]
        ) as? [String: Any]
        XCTAssertEqual(merged?["a"] as? String, "text")
        XCTAssertEqual((merged?["b"] as? [String: Any])?["c"] as? Int, 2)
        XCTAssertEqual(merged?["extra"] as? Bool, true)
    }
}
