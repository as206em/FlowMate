import Foundation

/// Cleans up model output so only the corrected text is used.
/// Models often add reasoning blocks, a preamble line, code fences or quotes around the answer.
enum OutputSanitizer {

    /// - Parameters:
    ///   - output: raw text from the model
    ///   - original: the text that was sent for proofreading (used to keep its own fences, quotes and edge whitespace)
    static func clean(_ output: String, original: String) -> String {
        var text = removeThinkingBlocks(output)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        text = removePreamble(text, original: original)
        text = removeWrapping(text, original: original)
        text = removeTrailingNote(text, original: original)
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // If cleaning removed everything, fall back to the trimmed raw output
        if text.isEmpty {
            text = removeThinkingBlocks(output).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return preserveEdgeWhitespace(of: original, in: text)
    }

    // MARK: - Steps

    /// Removes <think>…</think> (and similar) reasoning blocks, including an unclosed one at the start.
    static func removeThinkingBlocks(_ text: String) -> String {
        var result = text
        for tag in ["think", "thinking", "reasoning"] {
            let pattern = "<\(tag)>[\\s\\S]*?</\(tag)>"
            result = result.replacingOccurrences(of: pattern, with: "", options: [.regularExpression, .caseInsensitive])
            // Only a closing tag left: everything before it was reasoning
            if let range = result.range(of: "</\(tag)>", options: .caseInsensitive) {
                result = String(result[range.upperBound...])
            }
        }
        return result
    }

    /// Removes a first line like "Here is the corrected text:" or "Sure! Corrected version:".
    static func removePreamble(_ text: String, original: String = "") -> String {
        let lines = text.components(separatedBy: "\n")
        guard lines.count > 1, let first = lines.first?.trimmingCharacters(in: .whitespaces) else {
            return text
        }
        let lower = first.lowercased()
        let looksLikePreamble = first.hasSuffix(":") && first.count <= 80 && (
            lower.contains("corrected") || lower.contains("proofread") || lower.contains("revised")
            || lower.contains("here is") || lower.contains("here's") || lower.hasPrefix("sure")
            || lower.hasPrefix("certainly") || lower.hasPrefix("okay") || lower.hasPrefix("ok,")
        )
        // Keep it if the user's own text starts with a similar line
        let originalFirstLine = original.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n").first?.lowercased() ?? ""
        guard looksLikePreamble, !originalFirstLine.hasPrefix(lower.dropLast()) else { return text }
        return lines.dropFirst().joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Removes code fences or quotes around the whole answer, unless the original had them too.
    static func removeWrapping(_ text: String, original: String) -> String {
        let trimmedOriginal = original.trimmingCharacters(in: .whitespacesAndNewlines)
        var result = text

        if result.hasPrefix("```") && result.hasSuffix("```") && result.count > 6 && !trimmedOriginal.hasPrefix("```") {
            var lines = result.components(separatedBy: "\n")
            if lines.count >= 2 {
                lines.removeFirst() // ``` or ```markdown
                if lines.last?.trimmingCharacters(in: .whitespaces) == "```" {
                    lines.removeLast()
                }
                result = lines.joined(separator: "\n")
            }
        }

        for (open, close) in [("\"", "\""), ("“", "”"), ("'", "'")] {
            if result.count >= 2 && result.hasPrefix(open) && result.hasSuffix(close)
                && !trimmedOriginal.hasPrefix(open) {
                let inner = String(result.dropFirst(open.count).dropLast(close.count))
                // Only unwrap if the quote characters don't also appear inside (then they're probably real quotes)
                if !inner.contains(open) && !inner.contains(close) {
                    result = inner
                }
                break
            }
        }
        return result
    }

    /// Removes a trailing "Note: …" or "(I corrected …)" paragraph that the original didn't have.
    static func removeTrailingNote(_ text: String, original: String = "") -> String {
        let paragraphs = text.components(separatedBy: "\n\n")
        guard paragraphs.count > 1, let last = paragraphs.last?.trimmingCharacters(in: .whitespacesAndNewlines) else {
            return text
        }
        let lower = last.lowercased()
        let isNote = lower.hasPrefix("note:") || lower.hasPrefix("notes:") || lower.hasPrefix("(note")
            || lower.hasPrefix("changes made:") || lower.hasPrefix("explanation:")
        // Keep it if the user's own text has a similar note
        let notePrefix = String(lower.prefix(12))
        guard isNote, !original.lowercased().contains(notePrefix) else { return text }
        return paragraphs.dropLast().joined(separator: "\n\n")
    }

    /// Keeps the original's leading/trailing whitespace (e.g. a trailing newline in the selection),
    /// so replacing the selection doesn't join lines or eat indentation.
    static func preserveEdgeWhitespace(of original: String, in text: String) -> String {
        let leading = String(original.prefix(while: { $0.isWhitespace }))
        let trailing = String(original.reversed().prefix(while: { $0.isWhitespace }).reversed())
        guard !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return text }
        return leading + text + trailing
    }
}
