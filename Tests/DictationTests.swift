import XCTest
@testable import FlowMate

@MainActor
final class RealtimeTranscriptionTests: XCTestCase {
    func testURLFromBaseURL() {
        XCTAssertEqual(RealtimeTranscription.url(baseURL: "https://api.openai.com")?.absoluteString,
                       "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertEqual(RealtimeTranscription.url(baseURL: " https://api.openai.com/v1/ ")?.absoluteString,
                       "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertEqual(RealtimeTranscription.url(baseURL: "http://localhost:8080")?.absoluteString,
                       "ws://localhost:8080/v1/realtime?intent=transcription")
        XCTAssertNil(RealtimeTranscription.url(baseURL: "not a url"))
    }

    func testSessionUpdateCarriesModelInstructionsVocabularyAndLanguage() throws {
        let settings = DictationSettings(model: "gpt-live-transcribe", language: "ar",
                                         instructions: "Tickets for FlowMate", vocabulary: "FlowMate\n <Sprint> \n\nOKR")
        let json = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(RealtimeTranscription.sessionUpdate(settings: settings).utf8)) as? [String: Any])
        XCTAssertEqual(json["type"] as? String, "session.update")
        let session = try XCTUnwrap(json["session"] as? [String: Any])
        XCTAssertEqual(session["type"] as? String, "transcription")
        let input = try XCTUnwrap((session["audio"] as? [String: Any])?["input"] as? [String: Any])
        let format = try XCTUnwrap(input["format"] as? [String: Any])
        XCTAssertEqual(format["type"] as? String, "audio/pcm")
        XCTAssertEqual(format["rate"] as? Int, 24_000)
        XCTAssertTrue(input["turn_detection"] is NSNull)
        let transcription = try XCTUnwrap(input["transcription"] as? [String: Any])
        XCTAssertEqual(transcription["model"] as? String, "gpt-live-transcribe")
        XCTAssertEqual(transcription["prompt"] as? String, "Tickets for FlowMate")
        XCTAssertEqual(transcription["keywords"] as? [String], ["FlowMate", "Sprint", "OKR"])
        XCTAssertEqual(transcription["languages"] as? [String], ["ar"])
    }

    func testSessionUpdateLeavesOutEmptyOptions() throws {
        let settings = DictationSettings(language: "", instructions: "  ", vocabulary: "")
        let json = RealtimeTranscription.sessionUpdate(settings: settings)
        XCTAssertFalse(json.contains("languages"))
        XCTAssertFalse(json.contains("keywords"))
        XCTAssertFalse(json.contains("prompt"))
    }

    func testParsesServerEvents() {
        XCTAssertEqual(RealtimeTranscription.parse(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"a","content_index":0,"delta":"Hello,"}"#),
                       .delta(itemId: "a", text: "Hello,"))
        XCTAssertEqual(RealtimeTranscription.parse(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"a","transcript":"Hello, there."}"#),
                       .completed(itemId: "a", transcript: "Hello, there."))
        XCTAssertEqual(RealtimeTranscription.parse(#"{"type":"input_audio_buffer.committed","item_id":"b"}"#), .committed(itemId: "b"))
        XCTAssertEqual(RealtimeTranscription.parse(#"{"type":"error","error":{"message":"Bad key"}}"#), .error("Bad key"))
        XCTAssertEqual(RealtimeTranscription.parse(#"{"type":"session.updated"}"#), .other)
        XCTAssertEqual(RealtimeTranscription.parse("garbage"), .other)
    }

    func testAssemblerStreamsThenReplacesAndKeepsOrder() {
        var assembler = TranscriptAssembler()
        assembler.apply(.delta(itemId: "1", text: "fix the"))
        assembler.apply(.delta(itemId: "1", text: " login"))
        XCTAssertEqual(assembler.text, "fix the login")
        assembler.commitSent()
        assembler.apply(.committed(itemId: "1"))
        assembler.apply(.delta(itemId: "2", text: "then ship"))
        // Item 2 finishes before item 1: order stays
        assembler.apply(.completed(itemId: "2", transcript: "Then ship it."))
        XCTAssertFalse(assembler.isSettled)
        assembler.apply(.completed(itemId: "1", transcript: "Fix the login bug."))
        XCTAssertEqual(assembler.text, "Fix the login bug. Then ship it.")
        XCTAssertTrue(assembler.isSettled)
        // Late deltas don't change a finished item
        XCTAssertFalse(assembler.apply(.delta(itemId: "1", text: " extra")))
    }

    func testAssemblerWaitsForUnconfirmedCommit() {
        var assembler = TranscriptAssembler()
        assembler.commitSent()
        XCTAssertFalse(assembler.isSettled)
        assembler.apply(.committed(itemId: "x"))
        assembler.apply(.completed(itemId: "x", transcript: "Done"))
        XCTAssertTrue(assembler.isSettled)
    }

    func testPauseDetectorCommitsAfterSpeechThenSilence() {
        var detector = PauseDetector()
        // Silence alone never commits
        for _ in 0..<20 { XCTAssertFalse(detector.feed(level: 0.001, duration: 0.1)) }
        // Speech, then a pause
        for _ in 0..<5 { XCTAssertFalse(detector.feed(level: 0.1, duration: 0.1)) }
        XCTAssertTrue(detector.hasSpeech)
        var committed = false
        for _ in 0..<7 { committed = detector.feed(level: 0.001, duration: 0.1) || committed }
        XCTAssertTrue(committed)
        XCTAssertFalse(detector.hasSpeech)
    }

    func testPauseDetectorIgnoresAShortBlip() {
        var detector = PauseDetector()
        XCTAssertFalse(detector.feed(level: 0.1, duration: 0.1))
        for _ in 0..<20 { XCTAssertFalse(detector.feed(level: 0.001, duration: 0.1)) }
    }

    func testSpliceAddsSpacesWhereNeeded() {
        let middle = DictationSplice(base: "Fix bug", range: NSRange(location: 3, length: 0))
        XCTAssertEqual(middle.apply("the login"), "Fix the login bug")
        XCTAssertEqual(middle.caret(after: "the login"), 13)

        let end = DictationSplice(appendingTo: "Notes:")
        XCTAssertEqual(end.apply("call Sam"), "Notes: call Sam")
        XCTAssertEqual(DictationSplice(appendingTo: "").apply(" hello "), "hello")
        XCTAssertEqual(DictationSplice(appendingTo: "Line\n").apply("next"), "Line\nnext")

        // Before punctuation: no extra space
        let beforeDot = DictationSplice(base: "Call .", range: NSRange(location: 5, length: 0))
        XCTAssertEqual(beforeDot.apply("Sam"), "Call Sam.")

        // Replaces a selection
        let selection = DictationSplice(base: "Fix old thing", range: NSRange(location: 4, length: 3))
        XCTAssertEqual(selection.apply("new"), "Fix new thing")

        // A range past the end is clamped
        XCTAssertEqual(DictationSplice(base: "ab", range: NSRange(location: 9, length: 4)).apply("c"), "ab c")
    }

    func testTitleCleanup() {
        XCTAssertEqual(DictationController.clean("Fix the login bug.", for: .title), "Fix the login bug")
        XCTAssertEqual(DictationController.clean("\"Fix it\"\n", for: .title), "Fix it")
        XCTAssertEqual(DictationController.clean("Fix\nthe bug", for: .title), "Fix the bug")
        XCTAssertEqual(DictationController.clean("Wait...", for: .title), "Wait...")
        XCTAssertEqual(DictationController.clean("Para one.\n\nTwo.", for: .description), "Para one.\n\nTwo.")
    }

    func testProofreadingPromptHasFieldRulesAndUserContext() {
        let settings = DictationSettings(instructions: "Mobile app tickets", vocabulary: "FlowMate")
        let title = settings.proofreadingPrompt(for: .title)
        XCTAssertTrue(title.contains("no trailing period"))
        XCTAssertTrue(title.contains("Mobile app tickets"))
        XCTAssertTrue(title.contains("FlowMate"))
        XCTAssertTrue(settings.proofreadingPrompt(for: .description).contains("Markdown"))
    }

    func testOlderConfigGetsDictationDefaults() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("dictation-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        try #"{"app":{"theme":"dark"}}"#.write(to: url, atomically: true, encoding: .utf8)
        let config = try XCTUnwrap(ConfigurationManager.loadConfiguration(from: url))
        XCTAssertEqual(config.app.theme, "dark")
        XCTAssertEqual(config.app.dictation, DictationSettings())
        XCTAssertFalse(config.app.dictation.enabled)
    }
}

// MARK: - Controller

private final class FakeTransport: TranscriptionTransport {
    var sent: [String] = []
    var connectedURL: URL?
    var apiKey: String?
    var onMessage: ((String) -> Void)?
    var onClose: ((Error?) -> Void)?
    var closed = false

    func connect(url: URL, apiKey: String, onMessage: @escaping (String) -> Void, onClose: @escaping (Error?) -> Void) {
        connectedURL = url
        self.apiKey = apiKey
        self.onMessage = onMessage
        self.onClose = onClose
    }
    func send(_ text: String) { sent.append(text) }
    func close() { closed = true }

    var commits: Int { sent.filter { $0 == RealtimeTranscription.commit }.count }
}

private final class FakeCapture: AudioCapturing {
    var onChunk: ((Data, Float, TimeInterval) -> Void)?
    var stopped = false
    var startError: Error?
    func start(onChunk: @escaping (Data, Float, TimeInterval) -> Void) throws {
        if let startError { throw startError }
        self.onChunk = onChunk
    }
    func stop() { stopped = true }
}

private struct FakePermission: MicrophonePermission {
    var status: MicrophoneAccess
    func request() async -> Bool { status != .denied }
}

@MainActor
final class DictationControllerTests: XCTestCase {
    private var controller: DictationController!
    private var transport: FakeTransport!
    private var capture: FakeCapture!
    private var shown: [String] = []
    private var finished: [String] = []
    private var proofread: [String] = []
    private var ended = 0

    override func setUp() async throws {
        controller = DictationController()
        transport = FakeTransport()
        capture = FakeCapture()
        controller.settings = DictationSettings(enabled: true)
        controller.openAIKey = { " sk-test " }
        controller.makeTransport = { [unowned self] in self.transport }
        controller.makeCapture = { [unowned self] in self.capture }
        controller.permission = FakePermission(status: .allowed)
        controller.proofreadText = { text, _ in .success(correctedText: text.capitalized) }
        shown = []; finished = []; proofread = []; ended = 0
    }

    private func target(_ id: String = "notes-1") -> DictationController.Target {
        DictationController.Target(
            id: id, field: .description,
            update: { [unowned self] in self.shown.append($0) },
            finish: { [unowned self] in self.finished.append($0) },
            proofread: { [unowned self] in self.proofread.append($0) },
            end: { [unowned self] in self.ended += 1 }
        )
    }

    /// Lets the main queue deliver audio chunks and finish async work
    private func settle() async {
        for _ in 0..<5 {
            await Task.yield()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func speak(seconds: Double, level: Float) async {
        for _ in 0..<Int(seconds * 10) { capture.onChunk?(Data(repeating: 1, count: 4800), level, 0.1) }
        await settle()
    }

    private func server(_ json: String) { transport.onMessage?(json) }

    func testFullDictationStreamsCommitsAndProofreads() async {
        await controller.start(target())
        XCTAssertEqual(controller.phase, .listening)
        XCTAssertEqual(controller.activeId, "notes-1")
        XCTAssertEqual(transport.apiKey, "sk-test")
        XCTAssertEqual(transport.connectedURL?.absoluteString, "wss://api.openai.com/v1/realtime?intent=transcription")
        XCTAssertTrue(transport.sent.first?.contains("session.update") == true)

        await speak(seconds: 0.5, level: 0.2)
        XCTAssertTrue(transport.sent.contains { $0.contains("input_audio_buffer.append") })
        server(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"fix the"}"#)
        XCTAssertEqual(shown.last, "fix the")

        // A pause commits the turn
        await speak(seconds: 0.8, level: 0)
        XCTAssertEqual(transport.commits, 1)
        server(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#)
        server(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"fix the login"}"#)
        XCTAssertEqual(shown.last, "fix the login")

        controller.stop()
        // Nothing new was said, so no extra commit, and everything is settled
        XCTAssertEqual(transport.commits, 1)
        XCTAssertTrue(capture.stopped)
        XCTAssertTrue(transport.closed)
        XCTAssertEqual(finished, ["fix the login"])
        XCTAssertEqual(controller.phase, .proofreading)
        await settle()
        XCTAssertEqual(proofread, ["Fix The Login"])
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(controller.activeId)
    }

    func testStopCommitsTheLastTurnAndWaitsForIt() async {
        await controller.start(target())
        await speak(seconds: 0.5, level: 0.2)
        server(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"call Sam"}"#)
        controller.stop()
        XCTAssertEqual(transport.commits, 1)
        XCTAssertEqual(controller.phase, .finishing)
        XCTAssertTrue(finished.isEmpty)
        server(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#)
        server(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"Call Sam."}"#)
        XCTAssertEqual(finished, ["Call Sam."])
    }

    func testTimeoutFinishesWithWhatStreamed() async {
        controller.finishTimeout = 0.05
        await controller.start(target())
        await speak(seconds: 0.5, level: 0.2)
        server(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"partial words"}"#)
        controller.stop()
        try? await Task.sleep(nanoseconds: 150_000_000)
        await settle()
        XCTAssertEqual(finished, ["partial words"])
    }

    func testNoProofreadingWhenTurnedOff() async {
        controller.settings.proofreadAfter = false
        await controller.start(target())
        await speak(seconds: 0.5, level: 0.2)
        server(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"done"}"#)
        server(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#)
        controller.stop()
        server(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#)
        await settle()
        XCTAssertEqual(finished, ["done"])
        XCTAssertTrue(proofread.isEmpty)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testProofreadingFailureKeepsRawWordsAndSaysSo() async {
        controller.proofreadText = { _, _ in .failure(error: NSError(domain: "x", code: 1, userInfo: [NSLocalizedDescriptionKey: "Ollama is offline"])) }
        await controller.start(target())
        await speak(seconds: 0.5, level: 0.2)
        controller.stop()
        server(#"{"type":"input_audio_buffer.committed","item_id":"i1"}"#)
        server(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"keep me"}"#)
        await settle()
        XCTAssertEqual(finished, ["keep me"])
        XCTAssertTrue(proofread.isEmpty)
        XCTAssertEqual(controller.error?.targetId, "notes-1")
        XCTAssertTrue(controller.error?.message.contains("Ollama is offline") == true)
    }

    func testServerErrorStopsAndKeepsTranscript() async {
        await controller.start(target())
        server(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"some"}"#)
        server(#"{"type":"error","error":{"message":"Unknown parameter"}}"#)
        XCTAssertEqual(finished, ["some"])
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.error?.message, "Unknown parameter")
        XCTAssertTrue(capture.stopped)
    }

    func testCancelTakesTheTextBackOut() async {
        await controller.start(target())
        server(#"{"type":"conversation.item.input_audio_transcription.delta","item_id":"i1","delta":"oops"}"#)
        XCTAssertTrue(controller.canCancel)
        controller.cancel()
        XCTAssertEqual(shown.last, "")
        XCTAssertTrue(finished.isEmpty)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(controller.phase, .idle)
        // Late events of the old session are ignored
        server(#"{"type":"conversation.item.input_audio_transcription.completed","item_id":"i1","transcript":"late"}"#)
        XCTAssertTrue(finished.isEmpty)
    }

    func testSilenceOnlyEndsWithoutText() async {
        await controller.start(target())
        await speak(seconds: 1, level: 0)
        controller.stop()
        XCTAssertEqual(transport.commits, 0)
        XCTAssertTrue(finished.isEmpty)
        XCTAssertEqual(ended, 1)
        XCTAssertEqual(controller.phase, .idle)
    }

    func testNeedsAnAPIKey() async {
        controller.openAIKey = { "" }
        await controller.start(target())
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(transport.connectedURL)
        XCTAssertTrue(controller.error?.message.contains("OpenAI API key") == true)
    }

    func testDeniedMicrophone() async {
        controller.permission = FakePermission(status: .denied)
        await controller.start(target())
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNil(transport.connectedURL)
        XCTAssertTrue(controller.error?.message.contains("microphone") == true)
    }

    func testMicrophoneStartFailure() async {
        capture.startError = DictationError.noMicrophone
        await controller.start(target())
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertTrue(transport.closed)
        XCTAssertTrue(controller.error?.message.contains("No microphone") == true)
    }

    func testConnectionLostWhileListening() async {
        await controller.start(target())
        transport.onClose?(NSError(domain: "Dictation", code: 401, userInfo: [NSLocalizedDescriptionKey: "OpenAI didn't accept the API key."]))
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertEqual(controller.error?.message, "OpenAI didn't accept the API key.")
    }

    func testOnlyOneDictationAtATime() async {
        await controller.start(target("a"))
        controller.toggle(target("b"))
        await settle()
        XCTAssertEqual(controller.activeId, "a")
        // The same button stops it
        controller.toggle(target("a"))
        XCTAssertNotEqual(controller.phase, .listening)
    }
}
