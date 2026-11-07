import Foundation
import Alamofire

actor OllamaService: AIService {
    private var baseURL: String
    
    init(baseURL: String = AIProvider.ollama.defaultURL) {
        self.baseURL = baseURL
    }
    
    func listModels() async throws -> [String] {
        let url = "\(baseURL)/api/tags"

        let response = await AF.request(url, method: .get)
            .validate()
            .serializingDecodable(OllamaModelsResponse.self, automaticallyCancelling: true)
            .response

        switch response.result {
        case .success(let modelsResponse):
            return modelsResponse.models.map { $0.name }
        case .failure(let error):
            throw Self.readableError(error, data: response.data, statusCode: response.response?.statusCode)
        }
    }
    
    func generate(model: String, prompt: String) async throws -> String {
        await Logger.shared.info("OllamaService: Generating with model '\(model)', prompt length: \(prompt.count) chars")
        let url = "\(baseURL)/api/generate"
        let parameters: [String: Any] = [
            "model": model,
            "prompt": prompt,
            "stream": false
        ]
        
        // automaticallyCancelling: Cancel in the app also stops the generation in Ollama
        let response = await AF.request(url, method: .post, parameters: parameters, encoding: JSONEncoding.default)
            .validate()
            .serializingDecodable(OllamaGenerateResponse.self, automaticallyCancelling: true)
            .response

        switch response.result {
        case .success(let generateResponse):
            return generateResponse.response
        case .failure(let error):
            throw Self.readableError(error, data: response.data, statusCode: response.response?.statusCode)
        }
    }

    /// Turns Ollama's `{"error": "..."}` reply into a readable error that keeps the HTTP status as its code.
    private static func readableError(_ error: AFError, data: Data?, statusCode: Int?) -> Error {
        if error.isExplicitlyCancelledError {
            return CancellationError()
        }
        if let data, let reply = try? JSONDecoder().decode(OllamaErrorResponse.self, from: data) {
            return NSError(domain: "OllamaService", code: statusCode ?? -1,
                           userInfo: [NSLocalizedDescriptionKey: "Ollama: \(reply.error)"])
        }
        if let statusCode, !(200...299).contains(statusCode) {
            return NSError(domain: "OllamaService", code: statusCode,
                           userInfo: [NSLocalizedDescriptionKey: "Ollama returned HTTP \(statusCode)"])
        }
        return error
    }
}

struct OllamaErrorResponse: Codable {
    let error: String
}

struct OllamaModelsResponse: Codable {
    let models: [OllamaModel]
}

struct OllamaModel: Codable {
    let name: String
}

struct OllamaGenerateResponse: Codable {
    let response: String
}
