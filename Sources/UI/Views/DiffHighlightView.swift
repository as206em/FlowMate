import SwiftUI

struct DiffHighlightView: View {
    let originalText: String
    let correctedText: String

    /// Highlighted texts, computed once per view instead of on every render
    private let diff: TextDiff.Result?

    init(originalText: String, correctedText: String) {
        self.originalText = originalText
        self.correctedText = correctedText
        self.diff = (originalText.isEmpty || correctedText.isEmpty)
            ? nil
            : TextDiff.compute(original: originalText, corrected: correctedText)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                if let diff {
                    if diff.isTooLarge {
                        Text("This text is too long to highlight every change.")
                            .font(Focus.meta)
                            .foregroundColor(Focus.text3)
                    }
                    textBlock("Original", diff.original, fill: Focus.sidebar, border: Focus.hairline)
                    textBlock("Corrected", diff.corrected, fill: Focus.raised, border: Focus.ok.opacity(0.35))
                } else {
                    // No original to compare with: show the result only
                    textBlock(nil, AttributedString(correctedText), fill: Focus.raised, border: Focus.hairline)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
        }
    }

    private func textBlock(_ title: String?, _ text: AttributedString, fill: Color, border: Color) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                FocusCaption(text: title)
            }
            Text(text)
                .font(Focus.body)
                .foregroundColor(Focus.text)
                .textSelection(.enabled)
                .lineSpacing(3)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: Focus.radiusCard).fill(fill))
                .overlay(RoundedRectangle(cornerRadius: Focus.radiusCard).strokeBorder(border, lineWidth: 1))
        }
    }
}

/// Word-level comparison of the original and corrected text.
enum TextDiff {
    struct Result {
        let original: AttributedString
        let corrected: AttributedString
        /// True when the texts were too large to compare and are shown without highlights
        let isTooLarge: Bool
        /// Number of removed and added tokens (for tests)
        let removedCount: Int
        let insertedCount: Int
    }

    /// Above this many tokens per text, highlighting is skipped to keep the dialog responsive
    static let maxTokens = 5000

    static func compute(original: String, corrected: String) -> Result {
        let originalTokens = tokenize(original)
        let correctedTokens = tokenize(corrected)

        guard originalTokens.count <= maxTokens, correctedTokens.count <= maxTokens else {
            return Result(original: AttributedString(original), corrected: AttributedString(corrected),
                          isTooLarge: true, removedCount: 0, insertedCount: 0)
        }

        // Myers diff from the standard library: fast when the texts are similar
        let difference = correctedTokens.difference(from: originalTokens)
        var removed = Set<Int>()
        var inserted = Set<Int>()
        for change in difference {
            switch change {
            case .remove(let offset, _, _): removed.insert(offset)
            case .insert(let offset, _, _): inserted.insert(offset)
            }
        }

        return Result(
            original: build(originalTokens, highlighted: removed, isOriginal: true),
            corrected: build(correctedTokens, highlighted: inserted, isOriginal: false),
            isTooLarge: false,
            removedCount: removed.count,
            insertedCount: inserted.count
        )
    }

    /// Splits text into words, runs of whitespace, and single punctuation characters.
    /// Works on Characters, so emoji and accented letters are never split.
    static func tokenize(_ text: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var currentKind: Int? = nil // 0 = word, 1 = whitespace

        for character in text {
            let kind: Int?
            if character.isWhitespace {
                kind = 1
            } else if character.isLetter || character.isNumber || character == "'" || character == "’" {
                kind = 0
            } else {
                kind = nil // punctuation/symbols/emoji: one token each
            }

            if let kind, kind == currentKind {
                current.append(character)
            } else {
                if !current.isEmpty { tokens.append(current) }
                current = String(character)
                currentKind = kind
            }
        }
        if !current.isEmpty { tokens.append(current) }
        return tokens
    }

    /// Joins tokens into one AttributedString, highlighting the changed ones.
    /// Whitespace-only changes are left unhighlighted to avoid noise.
    private static func build(_ tokens: [String], highlighted: Set<Int>, isOriginal: Bool) -> AttributedString {
        var result = AttributedString()
        for (index, token) in tokens.enumerated() {
            var piece = AttributedString(token)
            if highlighted.contains(index) && !token.allSatisfy(\.isWhitespace) {
                if isOriginal {
                    piece.backgroundColor = Focus.riskTint.fill
                    piece.foregroundColor = Focus.riskTint.text
                    piece.strikethroughStyle = .single
                } else {
                    piece.backgroundColor = Focus.ok.opacity(0.14)
                    piece.foregroundColor = Focus.ok
                    piece.font = Focus.body.weight(.semibold)
                }
            }
            result.append(piece)
        }
        return result
    }
}
