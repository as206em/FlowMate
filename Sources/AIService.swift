import Foundation

protocol AIService {
    init(baseURL: String)
    func listModels() async throws -> [String]
    func generate(model: String, prompt: String) async throws -> String
}
