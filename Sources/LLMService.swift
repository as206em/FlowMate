import Foundation

protocol LLMService: Sendable {
    func listModels() async throws -> [String]
    func generate(model: String, prompt: String) async throws -> String
    func updateBaseURL(_ url: String) async
}

enum LLMProvider: String, CaseIterable, Identifiable {
    case ollama, openai
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .ollama: return "Ollama"
        case .openai: return "OpenAI"
        }
    }
}
