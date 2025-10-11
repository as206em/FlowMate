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
        await Logger.shared.debug("OpenAIService: Attempting to fetch models from URL: \(url)")
        await Logger.shared.debug("OpenAIService: Using API key: \(apiKey.isEmpty ? "EMPTY" : "SET")")
        
        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await Logger.shared.error("OpenAIService: Invalid response type: \(type(of: response))")
                throw NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            await Logger.shared.debug("OpenAIService: Response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                await Logger.shared.error("OpenAIService: Error response: \(responseString)")
                throw NSError(domain: "OpenAIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: \(responseString)"])
            }
            
            let decoder = JSONDecoder()
            let modelsResponse = try decoder.decode(OpenAIModelsResponse.self, from: data)
            let modelIds = modelsResponse.data.map { $0.id }
            await Logger.shared.info("OpenAIService: Successfully fetched \(modelIds.count) models: \(modelIds)")
            return modelIds
            
        } catch {
            await Logger.shared.error("OpenAIService: Error in listModels: \(error.localizedDescription)")
            let nsError = error as NSError
            await Logger.shared.error("OpenAIService: Error domain: \(nsError.domain), code: \(nsError.code)")
            throw error
        }
    }
    
    func generate(model: String, prompt: String) async throws -> String {
        let url = "\(baseURL)/v1/chat/completions"
        await Logger.shared.info("OpenAIService: Attempting to generate response from URL: \(url)")
        await Logger.shared.debug("OpenAIService: Using model: \(model)")
        await Logger.shared.debug("OpenAIService: Prompt length: \(prompt.count) characters")
        
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
        
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            
            guard let httpResponse = response as? HTTPURLResponse else {
                await Logger.shared.error("OpenAIService: Invalid response type in generate: \(type(of: response))")
                throw NSError(domain: "OpenAIService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }
            
            await Logger.shared.debug("OpenAIService: Generate response status code: \(httpResponse.statusCode)")
            
            if httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                await Logger.shared.error("OpenAIService: Generate error response: \(responseString)")
                
                if let errorResponse = try? JSONDecoder().decode(OpenAIErrorResponse.self, from: data) {
                    await Logger.shared.error("OpenAIService: Generate API error: \(errorResponse.error.message)")
                    throw NSError(domain: "OpenAIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.error.message])
                } else {
                    throw NSError(domain: "OpenAIService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to generate response: \(responseString)"])
                }
            }
            
            let decoder = JSONDecoder()
            let completionResponse = try decoder.decode(OpenAIChatCompletionResponse.self, from: data)
            let content = completionResponse.choices.first?.message.content ?? ""
            await Logger.shared.info("OpenAIService: Successfully generated response, length: \(content.count) characters")
            return content
            
        } catch {
            await Logger.shared.error("OpenAIService: Error in generate: \(error.localizedDescription)")
            let nsError = error as NSError
            await Logger.shared.error("OpenAIService: Generate error domain: \(nsError.domain), code: \(nsError.code)")
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
