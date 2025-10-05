import Foundation

enum AIProvider: String, CaseIterable {
    case ollama = "Ollama"
    case openai = "OpenAI"
    
    var displayName: String { self.rawValue }
}
