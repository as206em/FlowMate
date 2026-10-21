import Foundation

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
            
            // Check if we should retry
            if currentAttempt < maxRetries {
                // Wait briefly before retry
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                
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
}
