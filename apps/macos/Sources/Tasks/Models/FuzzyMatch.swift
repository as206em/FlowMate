import Foundation

/// Fuzzy matching for the ⌘K palette and the single-key pickers: a score for how well typed text
/// matches a name, or nil when it doesn't. Higher is better:
/// exact > starts with > a word starts with > contains > initials or letters in order.
enum FuzzyMatch {
    static func score(_ query: String, in text: String) -> Int? {
        let q = normalized(query)
        guard !q.isEmpty else { return 0 }
        let t = normalized(text)
        guard !t.isEmpty else { return nil }
        if t == q { return 1000 }
        if t.hasPrefix(q) { return 900 - min(t.count - q.count, 100) }
        let words = t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
        if words.contains(where: { $0.hasPrefix(q) }) { return 800 - min(t.count - q.count, 100) }
        if t.contains(q) { return 700 - min(t.count - q.count, 100) }
        // Several words typed: each one starts a word of the text, in any order ("bet lau")
        let parts = q.split(separator: " ").map(String.init)
        if parts.count > 1, parts.allSatisfy({ part in words.contains { $0.hasPrefix(part) } }) {
            return 600 - min(t.count, 100)
        }
        // Initials: "bl" for "Beta launch"
        let initials = String(words.compactMap(\.first))
        if q.count > 1, initials.hasPrefix(q.replacingOccurrences(of: " ", with: "")) { return 500 - min(t.count, 100) }
        // Letters in order, tighter runs score higher ("btlnch")
        let compact = q.replacingOccurrences(of: " ", with: "")
        guard compact.count > 1 else { return nil }
        var gaps = 0
        var index = t.startIndex
        for character in compact {
            guard let found = t[index...].firstIndex(of: character) else { return nil }
            gaps += t.distance(from: index, to: found)
            index = t.index(after: found)
        }
        return max(100, 400 - gaps * 10 - min(t.count, 100))
    }

    /// The best score over several names (a title and its keywords).
    static func score(_ query: String, in texts: [String]) -> Int? {
        texts.compactMap { score(query, in: $0) }.max()
    }

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }
}
