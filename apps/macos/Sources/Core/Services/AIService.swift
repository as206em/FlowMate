import Foundation

protocol AIService {
    func listModels() async throws -> [String]
    func generate(model: String, prompt: String) async throws -> String
}

// Default initializer requirement removed to allow flexibility
