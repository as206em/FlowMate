import AVFoundation
import AppKit
import Foundation

/// Records the microphone as 24 kHz mono 16-bit PCM chunks
protocol AudioCapturing: AnyObject {
    /// `onChunk` runs on an audio thread with the PCM data, its loudness (RMS, 0…1) and its length in seconds
    func start(onChunk: @escaping (Data, Float, TimeInterval) -> Void) throws
    func stop()
}

enum DictationError: LocalizedError {
    case noMicrophone
    case audioFormat

    var errorDescription: String? {
        switch self {
        case .noMicrophone: return "No microphone found. Connect one, or pick it in System Settings › Sound › Input."
        case .audioFormat: return "Couldn't read audio from the microphone."
        }
    }
}

final class MicrophoneCapture: AudioCapturing {
    private let engine = AVAudioEngine()
    private var running = false

    func start(onChunk: @escaping (Data, Float, TimeInterval) -> Void) throws {
        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)
        guard inputFormat.sampleRate > 0, inputFormat.channelCount > 0 else { throw DictationError.noMicrophone }
        guard let outputFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: RealtimeTranscription.sampleRate,
                                               channels: 1, interleaved: true),
              let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw DictationError.audioFormat
        }
        let ratio = RealtimeTranscription.sampleRate / inputFormat.sampleRate

        // ~100 ms of audio per chunk
        input.installTap(onBus: 0, bufferSize: AVAudioFrameCount(inputFormat.sampleRate / 10), format: inputFormat) { buffer, _ in
            let level = Self.rms(buffer)
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 32)
            guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else { return }
            var supplied = false
            var error: NSError?
            converter.convert(to: output, error: &error) { _, status in
                if supplied {
                    status.pointee = .noDataNow
                    return nil
                }
                supplied = true
                status.pointee = .haveData
                return buffer
            }
            guard error == nil, output.frameLength > 0, let samples = output.int16ChannelData else { return }
            let data = Data(bytes: samples[0], count: Int(output.frameLength) * MemoryLayout<Int16>.size)
            onChunk(data, level, Double(output.frameLength) / RealtimeTranscription.sampleRate)
        }
        engine.prepare()
        do {
            try engine.start()
        } catch {
            input.removeTap(onBus: 0)
            throw error
        }
        running = true
    }

    func stop() {
        guard running else { return }
        running = false
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
    }

    /// Loudness of the first channel
    private static func rms(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0], buffer.frameLength > 0 else { return 0 }
        let count = Int(buffer.frameLength)
        var sum: Float = 0
        for i in 0..<count { sum += channel[i] * channel[i] }
        return (sum / Float(count)).squareRoot()
    }
}

/// Whether FlowMate may use the microphone
enum MicrophoneAccess: Equatable {
    case allowed
    case notAsked
    case denied
}

protocol MicrophonePermission {
    var status: MicrophoneAccess { get }
    /// Asks macOS the first time. - Returns: true when allowed
    func request() async -> Bool
}

struct SystemMicrophonePermission: MicrophonePermission {
    var status: MicrophoneAccess {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: return .allowed
        case .notDetermined: return .notAsked
        default: return .denied
        }
    }

    func request() async -> Bool {
        if status == .allowed { return true }
        return await AVCaptureDevice.requestAccess(for: .audio)
    }

    /// System Settings › Privacy & Security › Microphone
    static func openSystemSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") {
            NSWorkspace.shared.open(url)
        }
    }
}

/// A text WebSocket to the transcription service
protocol TranscriptionTransport: AnyObject {
    /// `onMessage` and `onClose` run on the main queue. `onClose` gets nil when FlowMate closed it.
    func connect(url: URL, apiKey: String, onMessage: @escaping (String) -> Void, onClose: @escaping (Error?) -> Void)
    func send(_ text: String)
    func close()
}

final class WebSocketTransport: TranscriptionTransport {
    private var task: URLSessionWebSocketTask?
    private var closed = false

    func connect(url: URL, apiKey: String, onMessage: @escaping (String) -> Void, onClose: @escaping (Error?) -> Void) {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 15
        let task = URLSession.shared.webSocketTask(with: request)
        self.task = task
        task.resume()
        receive(task, onMessage: onMessage, onClose: onClose)
    }

    private func receive(_ task: URLSessionWebSocketTask, onMessage: @escaping (String) -> Void, onClose: @escaping (Error?) -> Void) {
        task.receive { [weak self] result in
            DispatchQueue.main.async {
                guard let self, !self.closed else { return }
                switch result {
                case .success(.string(let text)):
                    onMessage(text)
                    self.receive(task, onMessage: onMessage, onClose: onClose)
                case .success(.data(let data)):
                    onMessage(String(decoding: data, as: UTF8.self))
                    self.receive(task, onMessage: onMessage, onClose: onClose)
                case .success:
                    self.receive(task, onMessage: onMessage, onClose: onClose)
                case .failure(let error):
                    self.closed = true
                    onClose(Self.describe(error, response: task.response))
                }
            }
        }
    }

    func send(_ text: String) {
        guard !closed else { return }
        task?.send(.string(text)) { _ in }
    }

    func close() {
        closed = true
        task?.cancel(with: .normalClosure, reason: nil)
        task = nil
    }

    /// Turns a failed handshake into something a person can act on
    private static func describe(_ error: Error, response: URLResponse?) -> Error {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        let message: String
        switch status {
        case 401: message = "OpenAI didn't accept the API key. Check it in Settings › AI providers."
        case 403: message = "This OpenAI key can't use live transcription."
        case 404: message = "OpenAI's realtime transcription isn't available at the OpenAI URL in Settings › AI providers."
        case 429: message = "OpenAI's rate limit or quota was reached. Try again in a moment."
        default:
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain, nsError.code == NSURLErrorNotConnectedToInternet {
                message = "You're offline."
            } else {
                message = "Lost the connection to OpenAI (\(status > 0 ? "HTTP \(status)" : error.localizedDescription))."
            }
        }
        return NSError(domain: "Dictation", code: status, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
