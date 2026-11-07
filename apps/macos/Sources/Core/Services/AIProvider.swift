import Foundation

enum AIProvider: String, CaseIterable {
    case ollama = "Ollama"
    case openai = "OpenAI"
    
    var displayName: String { self.rawValue }

    /// The address used when none is configured
    var defaultURL: String {
        switch self {
        case .ollama: return "http://127.0.0.1:11434"
        case .openai: return "https://api.openai.com"
        }
    }
}
