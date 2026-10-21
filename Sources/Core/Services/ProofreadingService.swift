import Foundation
import Alamofire

/// Protocol for proofreading service to enable mocking in tests
protocol ProofreadingServiceProtocol {
    func proofread(
        text: String,
        model: String,
        prompt: String,
        aiService: AIService,
        promptBuilder: PromptBuilderProtocol,
        maxRetries: Int
    ) async -> ProofreadingResult
}

/// Service responsible for proofreading operations with retry logic
final class ProofreadingService: ProofreadingServiceProtocol {
    
    /// Performs proofreading with automatic retry on failure
    /// - Parameters:
    ///   - text: The text to proofread
    ///   - model: The AI model to use
    ///   - prompt: The system prompt for proofreading
    ///   - aiService: The AI service to use for generation
    ///   - promptBuilder: The prompt builder to construct the final prompt
    ///   - maxRetries: Maximum number of retry attempts (default: 3)
    /// - Returns: ProofreadingResult indicating success or failure
    func proofread(
        text: String,
        model: String,
        prompt: String,
        aiService: AIService,
        promptBuilder: PromptBuilderProtocol,
        maxRetries: Int = 3
    ) async -> ProofreadingResult {
        return await performProofreadingWithRetry(
            text: text,
            model: model,
            prompt: prompt,
            aiService: aiService,
            promptBuilder: promptBuilder,
            maxRetries: maxRetries,
            currentAttempt: 0
        )
    }
    
    /// Recursive helper function for retry logic
    private func performProofreadingWithRetry(
        text: String,
        model: String,
        prompt: String,
        aiService: AIService,
        promptBuilder: PromptBuilderProtocol,
        maxRetries: Int,
        currentAttempt: Int
    ) async -> ProofreadingResult {
        do {
            await Logger.shared.debug("ProofreadingService: Performing proofreading (attempt \(currentAttempt + 1)/\(maxRetries + 1))")
            
            // Construct the final prompt
            let finalPrompt = promptBuilder.buildProofreadingPrompt(userPrompt: prompt, inputText: text)
            
            // Generate corrected text
            let rawOutput = try await aiService.generate(model: model, prompt: finalPrompt)
            // Strip reasoning blocks, preambles and wrapping the model may have added
            let corrected = OutputSanitizer.clean(rawOutput, original: text)
            if corrected.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                throw NSError(domain: "ProofreadingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "The model returned an empty result."])
            }
            
            await Logger.shared.info("ProofreadingService: Proofreading completed successfully")
            return .success(correctedText: corrected)
            
        } catch {
            await Logger.shared.error("ProofreadingService: Proofreading failed (attempt \(currentAttempt + 1)/\(maxRetries + 1))", error: error)

            // Stop at once when the user cancelled
            if Task.isCancelled || error is CancellationError {
                return .failure(error: CancellationError())
            }

            // Only retry errors that might go away (timeouts, dropped connections, server overload)
            if currentAttempt < maxRetries && Self.isRetryable(error) {
                // Wait briefly before retry; a cancel during the wait ends the run
                do {
                    try await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                } catch {
                    return .failure(error: CancellationError())
                }
                
                // Retry
                return await performProofreadingWithRetry(
                    text: text,
                    model: model,
                    prompt: prompt,
                    aiService: aiService,
                    promptBuilder: promptBuilder,
                    maxRetries: maxRetries,
                    currentAttempt: currentAttempt + 1
                )
            } else {
                await Logger.shared.error("ProofreadingService: Proofreading failed after all retries")
                return .failure(error: error)
            }
        }
    }

    /// True for errors where trying again can help. Wrong model, bad API key, invalid URL
    /// or a cut-off result will fail the same way every time.
    static func isRetryable(_ error: Error) -> Bool {
        let nsError = underlyingError(error) as NSError
        if nsError.domain == NSURLErrorDomain {
            let retryableCodes: Set<Int> = [
                NSURLErrorTimedOut, NSURLErrorNetworkConnectionLost, NSURLErrorCannotConnectToHost,
                NSURLErrorNotConnectedToInternet, NSURLErrorCannotFindHost, NSURLErrorDNSLookupFailed
            ]
            return retryableCodes.contains(nsError.code)
        }
        // HTTP status from the services: retry rate limits and server errors only
        if nsError.domain == "OpenAIService" || nsError.domain == "OllamaService" {
            return nsError.code == 429 || (500...599).contains(nsError.code)
        }
        return false
    }

    /// Unwraps Alamofire's wrapper so the URL error inside can be checked.
    private static func underlyingError(_ error: Error) -> Error {
        if let afError = error as? AFError, let underlying = afError.underlyingError {
            return underlying
        }
        return error
    }
}
