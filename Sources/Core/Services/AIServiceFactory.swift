import Foundation

struct AIConfiguration {
    let ollamaURL: String
    let openAIURL: String
    let openAIAPIKey: String
    let qwenTokenFilePath: String

    static var `default`: AIConfiguration {
        return AIConfiguration(
            ollamaURL: "http://127.0.0.1:11434",
            openAIURL: "https://api.openai.com",
            openAIAPIKey: "",
            qwenTokenFilePath: ""
        )
    }
}

class AIServiceFactory {
    static func createService(for provider: AIProvider, configuration: AIConfiguration) -> AIService {
        switch provider {
        case .ollama:
            return OllamaService(baseURL: configuration.ollamaURL)
        case .openai:
            return OpenAIService(baseURL: configuration.openAIURL, apiKey: configuration.openAIAPIKey)
        case .qwen:
            return QwenService(tokenFilePath: configuration.qwenTokenFilePath)
        }
    }
}
