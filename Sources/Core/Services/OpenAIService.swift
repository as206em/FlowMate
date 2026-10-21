import Foundation

actor OpenAIService: AIService {
    private let baseURL: String
    private let apiKey: String
    
    /// Low randomness keeps corrections close to the original text.
    private static let proofreadingTemperature = 0.2

    init(baseURL: String = "https://api.openai.com", apiKey: String) {
        var trimmed = baseURL.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        self.baseURL = trimmed
        self.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Builds a request URL, throwing instead of crashing when the base URL is malformed.
    private func makeURL(_ path: String) throws -> URL {
        let string = "\(baseURL)\(path)"
        guard let url = URL(string: string), url.scheme != nil, url.host != nil else {
            throw NSError(domain: "OpenAIService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Invalid OpenAI URL: \"\(baseURL)\". Check it in Settings → AI Providers."])
        }
        return url
    }
    
    func listModels() async throws -> [String] {
        let url = "\(baseURL)/v1/models"
        await Logger.shared.debug("OpenAIService: Attempting to fetch models from URL: \(url)")
        await Logger.shared.debug("OpenAIService: Using API key: \(apiKey.isEmpty ? "EMPTY" : "SET")")
        
        var request = URLRequest(url: try makeURL("/v1/models"))
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
        
        do {
            return try await sendChatCompletion(model: model, prompt: prompt, temperature: Self.proofreadingTemperature)
        } catch let error as NSError where error.domain == "OpenAIService" && error.code == 400
                    && error.localizedDescription.lowercased().contains("temperature") {
            // Some models (e.g. reasoning models) only accept the default temperature. Retry without it.
            await Logger.shared.info("OpenAIService: Model rejected custom temperature, retrying with default")
            return try await sendChatCompletion(model: model, prompt: prompt, temperature: nil)
        }
    }

    private func sendChatCompletion(model: String, prompt: String, temperature: Double?) async throws -> String {
        var request = URLRequest(url: try makeURL("/v1/chat/completions"))
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        // No output token cap: a cap silently cuts long texts short
        let body = OpenAIChatCompletionRequest(
            model: model,
            messages: [.init(role: "user", content: prompt)],
            temperature: temperature
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
            guard let choice = completionResponse.choices.first else {
                throw NSError(domain: "OpenAIService", code: -3, userInfo: [NSLocalizedDescriptionKey: "OpenAI returned no result"])
            }

            // Never return a cut-off result: it would replace the user's text with a shorter version
            if choice.finish_reason == "length" {
                throw NSError(domain: "OpenAIService", code: -4, userInfo: [NSLocalizedDescriptionKey: "The result was cut off because the text is too long for this model. Try a shorter selection."])
            }

            let content = choice.message.content ?? ""
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
    /// Omitted from the JSON when nil, so the model's default is used
    let temperature: Double?
}

struct OpenAIMessage: Codable {
    let role: String
    let content: String
}

struct OpenAIChatCompletionResponse: Codable {
    let choices: [OpenAIChoice]
}

struct OpenAIChoice: Codable {
    let message: OpenAIResponseMessage
    let finish_reason: String?
}

/// Response messages can have null content (e.g. refusals), unlike request messages
struct OpenAIResponseMessage: Codable {
    let role: String
    let content: String?
}

struct OpenAIErrorResponse: Codable {
    let error: OpenAIError
}

struct OpenAIError: Codable {
    let message: String
}
