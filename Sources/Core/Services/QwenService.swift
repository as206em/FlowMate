import Foundation

actor QwenService: AIService {
    private let tokenFilePath: String
    private var cachedToken: QwenToken?
    private var lastTokenRead: Date?

    init(tokenFilePath: String) {
        self.tokenFilePath = tokenFilePath
    }

    func listModels() async throws -> [String] {
        let token = try await getValidToken()
        let url = "https://\(token.resourceURL)/api/v1/models"
        await Logger.shared.debug("QwenService: Attempting to fetch models from URL: \(url)")

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "GET"
        request.setValue("\(token.tokenType) \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await Logger.shared.error("QwenService: Invalid response type: \(type(of: response))")
                throw NSError(domain: "QwenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }

            await Logger.shared.debug("QwenService: Response status code: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                await Logger.shared.error("QwenService: Error response: \(responseString)")
                throw NSError(domain: "QwenService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to fetch models: \(responseString)"])
            }

            let decoder = JSONDecoder()
            let modelsResponse = try decoder.decode(QwenModelsResponse.self, from: data)
            let modelIds = modelsResponse.data.map { $0.id }
            await Logger.shared.info("QwenService: Successfully fetched \(modelIds.count) models: \(modelIds)")
            return modelIds

        } catch {
            await Logger.shared.error("QwenService: Error in listModels: \(error.localizedDescription)")
            let nsError = error as NSError
            await Logger.shared.error("QwenService: Error domain: \(nsError.domain), code: \(nsError.code)")
            throw error
        }
    }

    func generate(model: String, prompt: String) async throws -> String {
        let token = try await getValidToken()
        let url = "https://\(token.resourceURL)/api/v1/services/aigc/text-generation/generation"
        await Logger.shared.info("QwenService: Attempting to generate response from URL: \(url)")
        await Logger.shared.debug("QwenService: Using model: \(model)")
        await Logger.shared.debug("QwenService: Prompt length: \(prompt.count) characters")

        var request = URLRequest(url: URL(string: url)!)
        request.httpMethod = "POST"
        request.setValue("\(token.tokenType) \(token.accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body = QwenGenerationRequest(
            model: model,
            input: QwenInput(prompt: prompt),
            parameters: QwenParameters(temperature: 0.7, maxTokens: 1000)
        )

        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                await Logger.shared.error("QwenService: Invalid response type in generate: \(type(of: response))")
                throw NSError(domain: "QwenService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid response type"])
            }

            await Logger.shared.debug("QwenService: Generate response status code: \(httpResponse.statusCode)")

            if httpResponse.statusCode != 200 {
                let statusCode = httpResponse.statusCode
                let responseString = String(data: data, encoding: .utf8) ?? "Unable to decode response"
                await Logger.shared.error("QwenService: Generate error response: \(responseString)")

                if let errorResponse = try? JSONDecoder().decode(QwenErrorResponse.self, from: data) {
                    await Logger.shared.error("QwenService: Generate API error: \(errorResponse.message)")
                    throw NSError(domain: "QwenService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: errorResponse.message])
                } else {
                    throw NSError(domain: "QwenService", code: statusCode, userInfo: [NSLocalizedDescriptionKey: "Failed to generate response: \(responseString)"])
                }
            }

            let decoder = JSONDecoder()
            let generationResponse = try decoder.decode(QwenGenerationResponse.self, from: data)
            let content = generationResponse.output.text
            await Logger.shared.info("QwenService: Successfully generated response, length: \(content.count) characters")
            return content

        } catch {
            await Logger.shared.error("QwenService: Error in generate: \(error.localizedDescription)")
            let nsError = error as NSError
            await Logger.shared.error("QwenService: Generate error domain: \(nsError.domain), code: \(nsError.code)")
            throw error
        }
    }

    // MARK: - Token Management

    private func getValidToken() async throws -> QwenToken {
        // Check if we have a cached token that's still valid
        if let cached = cachedToken,
           let lastRead = lastTokenRead,
           Date().timeIntervalSince(lastRead) < 60, // Re-read every 60 seconds
           !cached.isExpired {
            return cached
        }

        // Read token from file
        let token = try await readTokenFile()

        // Check if token is expired
        if token.isExpired {
            await Logger.shared.error("QwenService: Token has expired. Please re-authenticate using the Qwen CLI.")
            throw NSError(
                domain: "QwenService",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Token expired. Please re-authenticate using: qwen auth login"]
            )
        }

        // Cache the token
        cachedToken = token
        lastTokenRead = Date()

        return token
    }

    private func readTokenFile() async throws -> QwenToken {
        await Logger.shared.debug("QwenService: Reading token file from: \(tokenFilePath)")

        let url = URL(fileURLWithPath: tokenFilePath)

        guard FileManager.default.fileExists(atPath: tokenFilePath) else {
            await Logger.shared.error("QwenService: Token file not found at: \(tokenFilePath)")
            throw NSError(
                domain: "QwenService",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Token file not found at: \(tokenFilePath)"]
            )
        }

        do {
            let data = try Data(contentsOf: url)
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            let token = try decoder.decode(QwenToken.self, from: data)
            await Logger.shared.debug("QwenService: Successfully read token file")
            return token
        } catch {
            await Logger.shared.error("QwenService: Failed to read or parse token file: \(error.localizedDescription)")
            throw NSError(
                domain: "QwenService",
                code: -4,
                userInfo: [NSLocalizedDescriptionKey: "Failed to read token file: \(error.localizedDescription)"]
            )
        }
    }
}

// MARK: - Token Models

struct QwenToken: Codable {
    let accessToken: String
    let refreshToken: String
    let tokenType: String
    let resourceURL: String
    let expiryDate: Int64

    var isExpired: Bool {
        let currentTimestamp = Int64(Date().timeIntervalSince1970 * 1000)
        return currentTimestamp >= expiryDate
    }
}

// MARK: - API Models

struct QwenModelsResponse: Codable {
    let data: [QwenModel]
}

struct QwenModel: Codable {
    let id: String
}

struct QwenGenerationRequest: Codable {
    let model: String
    let input: QwenInput
    let parameters: QwenParameters
}

struct QwenInput: Codable {
    let prompt: String
}

struct QwenParameters: Codable {
    let temperature: Double
    let maxTokens: Int

    enum CodingKeys: String, CodingKey {
        case temperature
        case maxTokens = "max_tokens"
    }
}

struct QwenGenerationResponse: Codable {
    let output: QwenOutput
}

struct QwenOutput: Codable {
    let text: String
}

struct QwenErrorResponse: Codable {
    let message: String
}
