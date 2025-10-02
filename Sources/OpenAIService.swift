import Foundation

actor OpenAIService: AIService {
    private let baseURL: String
    
    init(baseURL: String) {
        self.baseURL = baseURL
    }
    
    func listModels() async throws -> [String] {
        // Placeholder implementation
        return []
    }
    
    func generate(model: String, prompt: String) async throws -> String {
        // Placeholder implementation
        return ""
    }
}
