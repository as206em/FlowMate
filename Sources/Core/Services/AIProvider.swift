import Foundation

enum AIProvider: String, CaseIterable {
    case ollama = "Ollama"
    case openai = "OpenAI"
    case qwen = "Qwen"

    var displayName: String { self.rawValue }
}
