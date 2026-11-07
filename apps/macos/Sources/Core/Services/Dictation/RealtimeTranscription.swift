import Foundation

/// The messages of OpenAI's realtime transcription session (WebSocket, `intent=transcription`).
/// Audio is mono 16-bit PCM at 24 kHz. Turn detection is off: FlowMate commits the audio itself
/// at pauses and when you stop, and each commit comes back as one transcript item.
enum RealtimeTranscription {
    static let sampleRate: Double = 24_000

    /// wss://…/v1/realtime?intent=transcription from the OpenAI base URL in AI providers
    static func url(baseURL: String) -> URL? {
        var base = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while base.hasSuffix("/") { base.removeLast() }
        if base.hasPrefix("https://") {
            base = "wss://" + base.dropFirst("https://".count)
        } else if base.hasPrefix("http://") {
            base = "ws://" + base.dropFirst("http://".count)
        }
        // A base URL that already ends in /v1 keeps it once
        if base.hasSuffix("/v1") { base.removeLast(3) }
        guard let url = URL(string: base + "/v1/realtime?intent=transcription"),
              url.scheme == "wss" || url.scheme == "ws", url.host != nil else { return nil }
        return url
    }

    /// `session.update` that sets up transcription
    static func sessionUpdate(settings: DictationSettings) -> String {
        var transcription: [String: Any] = ["model": settings.model]
        let prompt = settings.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        if !prompt.isEmpty { transcription["prompt"] = prompt }
        if !settings.keywords.isEmpty { transcription["keywords"] = settings.keywords }
        if !settings.language.isEmpty { transcription["languages"] = [settings.language] }
        let message: [String: Any] = [
            "type": "session.update",
            "session": [
                "type": "transcription",
                "audio": [
                    "input": [
                        "format": ["type": "audio/pcm", "rate": Int(sampleRate)],
                        "transcription": transcription,
                        "turn_detection": NSNull()
                    ]
                ]
            ]
        ]
        return json(message)
    }

    static func append(_ pcm: Data) -> String {
        json(["type": "input_audio_buffer.append", "audio": pcm.base64EncodedString()])
    }

    static let commit = #"{"type":"input_audio_buffer.commit"}"#

    private static func json(_ object: [String: Any]) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return "{}" }
        return String(decoding: data, as: UTF8.self)
    }

    /// What the server sends that FlowMate cares about
    enum Event: Equatable {
        case committed(itemId: String)
        case delta(itemId: String, text: String)
        case completed(itemId: String, transcript: String)
        case failed(itemId: String, message: String)
        case error(String)
        case other
    }

    static func parse(_ text: String) -> Event {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = object["type"] as? String else { return .other }
        let itemId = object["item_id"] as? String ?? ""
        switch type {
        case "input_audio_buffer.committed":
            return .committed(itemId: itemId)
        case "conversation.item.input_audio_transcription.delta":
            return .delta(itemId: itemId, text: object["delta"] as? String ?? "")
        case "conversation.item.input_audio_transcription.completed":
            return .completed(itemId: itemId, transcript: object["transcript"] as? String ?? "")
        case "conversation.item.input_audio_transcription.failed":
            let error = object["error"] as? [String: Any]
            return .failed(itemId: itemId, message: error?["message"] as? String ?? "Transcription failed")
        case "error":
            let error = object["error"] as? [String: Any]
            return .error(error?["message"] as? String ?? "OpenAI returned an error")
        default:
            return .other
        }
    }
}

/// Builds the transcript from the server's items: streamed deltas while you speak, replaced by
/// each item's final transcript. Items keep the order they were first seen in, because final
/// transcripts of different turns can arrive out of order.
struct TranscriptAssembler: Equatable {
    private(set) var order: [String] = []
    private var texts: [String: String] = [:]
    private var finished: Set<String> = []
    /// Commits sent that the server hasn't confirmed yet
    private(set) var unconfirmedCommits = 0

    mutating func commitSent() { unconfirmedCommits += 1 }

    /// - Returns: true when the text changed
    @discardableResult
    mutating func apply(_ event: RealtimeTranscription.Event) -> Bool {
        switch event {
        case .committed(let id):
            unconfirmedCommits = max(0, unconfirmedCommits - 1)
            see(id)
            return false
        case .delta(let id, let text):
            see(id)
            guard !finished.contains(id), !text.isEmpty else { return false }
            texts[id, default: ""] += text
            return true
        case .completed(let id, let transcript):
            see(id)
            finished.insert(id)
            let changed = texts[id] != transcript
            texts[id] = transcript
            return changed
        case .failed(let id, _):
            // Keep whatever streamed for it
            see(id)
            finished.insert(id)
            return false
        case .error, .other:
            return false
        }
    }

    private mutating func see(_ id: String) {
        if !order.contains(id) { order.append(id) }
    }

    /// All items so far, joined with single spaces
    var text: String {
        order.compactMap { texts[$0]?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    /// True once every commit is confirmed and every item has its final transcript
    var isSettled: Bool {
        unconfirmedCommits == 0 && order.allSatisfy { finished.contains($0) }
    }
}

/// Decides when to commit: after a pause that follows some speech, so each sentence becomes
/// its own item and gets its final transcript while you keep talking.
struct PauseDetector {
    /// Audio louder than this counts as speech (RMS of samples in -1…1)
    var speechLevel: Float = 0.015
    /// How long a pause must be
    var pause: TimeInterval = 0.7
    /// How much speech a turn needs before a pause ends it
    var minimumSpeech: TimeInterval = 0.3

    private(set) var speechInTurn: TimeInterval = 0
    private var silence: TimeInterval = 0

    /// True when audio since the last commit has speech worth sending
    var hasSpeech: Bool { speechInTurn >= minimumSpeech }

    /// Feeds a chunk of audio. - Returns: true when this chunk ends a turn (commit now)
    mutating func feed(level: Float, duration: TimeInterval) -> Bool {
        if level >= speechLevel {
            speechInTurn += duration
            silence = 0
            return false
        }
        silence += duration
        guard hasSpeech, silence >= pause else { return false }
        reset()
        return true
    }

    mutating func reset() {
        speechInTurn = 0
        silence = 0
    }
}

/// Puts dictated text into a field's text at the place the cursor was, with a space on each
/// side when the neighbouring text needs one.
struct DictationSplice: Equatable {
    let base: String
    /// UTF-16 range of `base` the dictation replaces (the selection when it started)
    let range: NSRange

    init(base: String, range: NSRange) {
        let length = (base as NSString).length
        let location = min(max(0, range.location), length)
        self.base = base
        self.range = NSRange(location: location, length: min(max(0, range.length), length - location))
    }

    /// Dictation at the end of the text (titles)
    init(appendingTo base: String) {
        self.init(base: base, range: NSRange(location: (base as NSString).length, length: 0))
    }

    /// The text to insert, with the spaces it needs
    func insertion(_ dictated: String) -> String {
        let dictated = dictated.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dictated.isEmpty else { return "" }
        let ns = base as NSString
        var result = dictated
        if range.location > 0, let before = ns.substring(with: NSRange(location: range.location - 1, length: 1)).unicodeScalars.first,
           !CharacterSet.whitespacesAndNewlines.contains(before) {
            result = " " + result
        }
        let end = range.location + range.length
        if end < ns.length, let after = ns.substring(with: NSRange(location: end, length: 1)).unicodeScalars.first,
           !CharacterSet.whitespacesAndNewlines.contains(after), !CharacterSet.punctuationCharacters.contains(after) {
            result += " "
        }
        return result
    }

    /// The full text with `dictated` in place
    func apply(_ dictated: String) -> String {
        (base as NSString).replacingCharacters(in: range, with: insertion(dictated))
    }

    /// Where the cursor goes after the dictated text
    func caret(after dictated: String) -> Int {
        range.location + (insertion(dictated) as NSString).length
    }
}
