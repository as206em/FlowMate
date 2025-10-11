import Foundation

/// Result of a proofreading operation
enum ProofreadingResult {
    case success(correctedText: String)
    case failure(error: Error)
}
