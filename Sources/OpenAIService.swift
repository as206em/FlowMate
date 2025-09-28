import Foundation
import Alamofire
import SwiftUI

actor OpenAIService: LLMService {
    private var apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    
    init(apiKey: String = "") {
        self.apiKey = apiKey
    }
    
    func updateBaseURL(_ url: String) async {
        self.apiKey = url
    }
    
    func listModels() async throws -> [String] {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "API key is required"])
        }
        
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        let response = await AF.request("\(baseURL)/models", method: .get, headers: headers)
            .serializingDecodable(OpenAIModelsResponse.self)
            .response
        
        switch response.result {
        case .success(let modelsResponse):
            return modelsResponse.data.map { $0.id }.filter { $0.hasPrefix("gpt-") }
        case .failure(let error):
            throw error
        }
    }
    
    func generate(model: String, prompt: String) async throws -> String {
        guard !apiKey.isEmpty else {
            throw NSError(domain: "OpenAIService", code: 0, userInfo: [NSLocalizedDescriptionKey: "API key is required"])
        }
        
        let headers: HTTPHeaders = [
            "Authorization": "Bearer \(apiKey)",
            "Content-Type": "application/json"
        ]
        
        let parameters: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "user", "content": prompt]
            ],
            "temperature": 0.7,
            "max_tokens": 2000
        ]
        
        let response = await AF.request("\(baseURL)/chat/completions", method: .post, parameters: parameters, encoding: JSONEncoding.default, headers: headers)
            .serializingDecodable(OpenAIChatResponse.self)
            .response
        
        switch response.result {
        case .success(let chatResponse):
            return chatResponse.choices.first?.message.content ?? ""
        case .failure(let error):
            throw error
        }
    }
}

struct OpenAIModelsResponse: Codable {
    let data: [OpenAIModel]
}

struct OpenAIModel: Codable {
    let id: String
}

struct OpenAIChatResponse: Codable {
    let choices: [Choice]
}

struct Choice: Codable {
    let message: Message
}

struct Message: Codable {
    let content: String
}
