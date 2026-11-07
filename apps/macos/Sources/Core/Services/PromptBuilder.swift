import Foundation

/// Protocol for prompt building to enable mocking in tests
protocol PromptBuilderProtocol {
    func buildProofreadingPrompt(userPrompt: String, inputText: String) -> String
}

/// Service responsible for constructing prompts for AI services
final class PromptBuilder: PromptBuilderProtocol {
    
    /// Builds a complete proofreading prompt by combining user prompt with input text
    /// - Parameters:
    ///   - userPrompt: The system prompt defining proofreading behavior
    ///   - inputText: The text to be proofread
    /// - Returns: Complete prompt ready for AI service
    func buildProofreadingPrompt(userPrompt: String, inputText: String) -> String {
        return userPrompt + "\n\nText to proofread:\n" + inputText
    }
}
