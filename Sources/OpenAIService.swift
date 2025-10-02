import Foundation

actor OpenAIService: AIService {
    private let baseURL: String
    private let apiKey: String
    
    init(baseURL: String = "https://api.openai.com", apiKey: String) {
        self.baseURL = baseURL
        self.apiKey = apiKey
    }
    
    func listModels() async throws -> [String] {
        let url = "\(baseURL)/v1/models"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw NSError(domain: "OpenAIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models"])
        }
        
        let decoder = JSONDecoder()
        let modelsResponse = try decoder.decode(OpenAIModelsResponse.self, from: data)
        return modelsResponse.data.map { $0.id }
    }
    
    func generate(model: String, prompt: String) async throws -> String {
        let url = "\(baseURL)/v1/chat/completions"
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body = OpenAIChatCompletionRequest(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            temperature: 0.7,
            max_tokens: 1000
        )
        
        request.httpBody = try JSONEncoder().encode(body)
        
        let (data, response) = try await URLSession.shared.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200 else {
            let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data)
            throw NSError(domain: "OpenAIService", code: httpResponse.statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse?.error.message ?? "Failed to generate response"])
        }
        
        let decoder = JSONDecoder()
        let completionResponse = try decoder.decode(OpenAIChatCompletionResponse.self, from: data)
        return completionResponse.choices.first?.message.content ?? ""
    }
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Codable {
    let id: String
}

struct OpenAIChatCompletionRequest: Codable {
    let model: String
    let messages: [OpenAIMessage]
    let temperature: Double
    let max_tokens: Int
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatCompletionResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIMessage
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
}

struct OpenAIError: Codable {
    let message: String
}
