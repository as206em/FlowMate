import Foundation

/// Runs one dictation at a time: microphone → OpenAI realtime transcription → the field,
/// then proofreads what you said when you stop. The mic buttons talk to `shared`;
/// AppState fills in the settings, the OpenAI key and the proofreading.
@MainActor
final class DictationController: ObservableObject {
    static let shared = DictationController()

    enum Phase: Equatable {
        case idle
        case listening
        /// Stopped; waiting for the last transcripts
        case finishing
        case proofreading
    }

    /// A field that takes dictation
    struct Target {
        /// Which field, e.g. "title-<task id>"; the button with this id shows the state
        let id: String
        let field: DictationSettings.Field
        /// The transcript so far (raw), shown live in the field
        let update: (String) -> Void
        /// The final raw transcript when you stop
        let finish: (String) -> Void
        /// The proofread text, replacing the raw transcript
        let proofread: (String) -> Void
        /// Dictation is over; the field can be edited again
        let end: () -> Void
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var activeId: String?
    /// Microphone loudness, 0…1, for the button's pulse
    @Published private(set) var level: Float = 0
    /// The last problem, shown under the field it happened in
    @Published private(set) var error: (targetId: String, message: String)?
    @Published var settings = DictationSettings()

    // Filled in by AppState
    var openAIKey: () -> String = { "" }
    var openAIBaseURL: () -> String = { AIProvider.openai.defaultURL }
    var proofreadText: (String, DictationSettings.Field) async -> ProofreadingResult = { text, _ in .success(correctedText: text) }

    // Replaced by tests
    var makeCapture: () -> AudioCapturing = { MicrophoneCapture() }
    var makeTransport: () -> TranscriptionTransport = { WebSocketTransport() }
    var permission: MicrophonePermission = SystemMicrophonePermission()
    /// How long to wait for the last transcripts after you stop
    var finishTimeout: TimeInterval = 8
    /// A dictation stops by itself after this long
    var maximumLength: TimeInterval = 10 * 60

    private var target: Target?
    private var capture: AudioCapturing?
    private var transport: TranscriptionTransport?
    private var assembler = TranscriptAssembler()
    private var pauses = PauseDetector()
    private var session = UUID()
    private var errorClear: Task<Void, Never>?

    var isBusy: Bool { phase != .idle }

    /// Esc can still take the dictation back (not once it's being proofread)
    var canCancel: Bool { phase == .listening || phase == .finishing }

    func isActive(_ id: String) -> Bool { activeId == id }

    /// Why the mic can't be used right now (nil when it can)
    var unavailableReason: String? {
        if openAIKey().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "Dictation uses OpenAI. Add your OpenAI API key in Settings › AI providers."
        }
        if permission.status == .denied {
            return "FlowMate can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone."
        }
        return nil
    }

    /// The mic button: starts dictating into the target, or stops when it's already dictating there.
    func toggle(_ target: Target) {
        if activeId == target.id {
            if phase == .listening { stop() }
            return
        }
        guard phase == .idle else { return }
        Task { await start(target) }
    }

    func start(_ target: Target) async {
        guard phase == .idle else { return }
        clearError()
        if let reason = unavailableReason {
            show(reason, for: target.id)
            return
        }
        guard let url = RealtimeTranscription.url(baseURL: openAIBaseURL()) else {
            show("The OpenAI URL in Settings › AI providers isn't valid.", for: target.id)
            return
        }
        // Mark it busy before the permission prompt so a second click does nothing
        phase = .listening
        activeId = target.id
        guard await permission.request() else {
            reset()
            show("FlowMate can't use the microphone. Allow it in System Settings › Privacy & Security › Microphone.", for: target.id)
            return
        }

        let session = UUID()
        self.session = session
        self.target = target
        assembler = TranscriptAssembler()
        pauses = PauseDetector()

        let transport = makeTransport()
        self.transport = transport
        transport.connect(url: url, apiKey: openAIKey().trimmingCharacters(in: .whitespacesAndNewlines),
                          onMessage: { [weak self] text in self?.received(text, session: session) },
                          onClose: { [weak self] error in self?.closed(error, session: session) })
        transport.send(RealtimeTranscription.sessionUpdate(settings: settings))

        let capture = makeCapture()
        self.capture = capture
        do {
            try capture.start { [weak self] data, level, duration in
                DispatchQueue.main.async { self?.heard(data, level: level, duration: duration, session: session) }
            }
        } catch {
            fail(error.localizedDescription)
            return
        }
        Logger.shared.info("Dictation: Started (\(settings.model))")

        // A forgotten mic stops by itself
        let limit = maximumLength
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(limit * 1_000_000_000))
            guard let self, self.session == session, self.phase == .listening else { return }
            self.stop()
        }
    }

    /// Stops listening; the text is final once the last transcripts arrive.
    func stop() {
        guard phase == .listening else { return }
        capture?.stop()
        capture = nil
        level = 0
        if pauses.speechInTurn > 0 { commit() }
        phase = .finishing
        if assembler.isSettled {
            finalize()
            return
        }
        let session = self.session
        let timeout = finishTimeout
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, self.session == session, self.phase == .finishing else { return }
            Logger.shared.warning("Dictation: Gave up waiting for the last transcript")
            self.finalize()
        }
    }

    /// Stops and takes the dictated text back out.
    func cancel() {
        guard let target, phase == .listening || phase == .finishing else { return }
        Logger.shared.info("Dictation: Cancelled")
        target.update("")
        target.end()
        tearDown()
        reset()
    }

    // MARK: - Events

    private func heard(_ data: Data, level: Float, duration: TimeInterval, session: UUID) {
        guard self.session == session, phase == .listening else { return }
        transport?.send(RealtimeTranscription.append(data))
        // Quick rise, slow fall so the pulse is readable
        let shown = min(1, level * 8)
        self.level = shown > self.level ? shown : self.level * 0.8 + shown * 0.2
        if pauses.feed(level: level, duration: duration) { commit() }
    }

    private func commit() {
        transport?.send(RealtimeTranscription.commit)
        assembler.commitSent()
        pauses.reset()
    }

    private func received(_ text: String, session: UUID) {
        guard self.session == session, let target, phase == .listening || phase == .finishing else { return }
        let event = RealtimeTranscription.parse(text)
        if case .error(let message) = event {
            fail(message)
            return
        }
        if case .failed(_, let message) = event {
            Logger.shared.warning("Dictation: A transcript failed: \(message)")
        }
        if assembler.apply(event) { target.update(assembler.text) }
        if phase == .finishing, assembler.isSettled { finalize() }
    }

    private func closed(_ error: Error?, session: UUID) {
        guard self.session == session, phase == .listening || phase == .finishing else { return }
        if phase == .finishing {
            finalize()
        } else {
            fail(error?.localizedDescription ?? "The connection to OpenAI closed.")
        }
    }

    // MARK: - Ending

    private func finalize() {
        guard let target, phase == .finishing else { return }
        tearDown()
        let raw = assembler.text
        guard !raw.isEmpty else {
            target.update("")
            target.end()
            reset()
            return
        }
        target.finish(raw)
        Logger.shared.info("Dictation: Finished, \(raw.count) characters")
        guard settings.proofreadAfter else {
            target.end()
            reset()
            return
        }
        phase = .proofreading
        let session = self.session
        Task { [weak self] in
            guard let self else { return }
            let result = await self.proofreadText(raw, target.field)
            guard self.session == session else { return }
            switch result {
            case .success(let corrected):
                let cleaned = Self.clean(corrected, for: target.field)
                if !cleaned.isEmpty, cleaned != raw { target.proofread(cleaned) }
            case .failure(let error):
                if !(error is CancellationError) {
                    self.show("Proofreading didn't work, so your words are as you said them. \(error.localizedDescription)", for: target.id)
                }
            }
            target.end()
            self.reset()
        }
    }

    /// Something went wrong while listening: keep what was transcribed and say why.
    private func fail(_ message: String) {
        guard let target else { return }
        Logger.shared.error("Dictation: \(message)")
        tearDown()
        let raw = assembler.text
        if raw.isEmpty { target.update("") } else { target.finish(raw) }
        target.end()
        reset()
        show(message, for: target.id)
    }

    private func tearDown() {
        capture?.stop()
        capture = nil
        transport?.close()
        transport = nil
    }

    private func reset() {
        phase = .idle
        activeId = nil
        level = 0
        target = nil
        session = UUID()
    }

    private func show(_ message: String, for targetId: String) {
        error = (targetId, message)
        errorClear?.cancel()
        errorClear = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            guard !Task.isCancelled else { return }
            self?.error = nil
        }
    }

    func clearError() {
        errorClear?.cancel()
        error = nil
    }

    /// Titles stay on one line, without the quotes or trailing period a model may add
    nonisolated static func clean(_ text: String, for field: DictationSettings.Field) -> String {
        var text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard field == .title else { return text }
        text = text.components(separatedBy: .newlines).map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }.joined(separator: " ")
        if text.count > 1, let first = text.first, let last = text.last, first == last, "\"'“”".contains(first) {
            text = String(text.dropFirst().dropLast())
        } else if text.hasPrefix("“"), text.hasSuffix("”") {
            text = String(text.dropFirst().dropLast())
        }
        while text.hasSuffix("."), !text.hasSuffix("...") { text.removeLast() }
        return text.trimmingCharacters(in: .whitespaces)
    }
}
