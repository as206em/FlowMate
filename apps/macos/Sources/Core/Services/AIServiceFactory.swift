import Foundation

struct AIConfiguration {
    let ollamaURL: String
    let openAIURL: String
    let openAIAPIKey: String
    
    static var `default`: AIConfiguration {
        return AIConfiguration(
            ollamaURL: AIProvider.ollama.defaultURL,
            openAIURL: AIProvider.openai.defaultURL,
            openAIAPIKey: ""
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
        }
    }
}
