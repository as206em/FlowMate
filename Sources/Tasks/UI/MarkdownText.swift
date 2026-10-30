import Foundation
import SwiftUI

// Markdown for task descriptions: a small block parser for the Preview and the
// toolbar edits for the Write mode. Both mirror the reference design (FocusApp.dc.html).

/// One block of a task description.
struct MarkdownBlock: Equatable, Identifiable {
    enum Kind: Equatable {
        case heading2, heading3, paragraph, bullet, quote, code
        /// `- [ ] item`; `line` is the 0-based source line, for toggling
        case checklist(checked: Bool, line: Int)
    }

    let id: Int
    let kind: Kind
    /// Inline Markdown (raw text for code blocks)
    let text: String
}

enum MarkdownBlocks {
    /// Splits Markdown into blocks: `##`/`###` headings, paragraphs, `-` lists, `- [ ]` checklists, `>` quotes and fenced code.
    /// Lines are split on "\n" exactly like `MarkdownChecklist`, so checklist line numbers match.
    static func parse(_ source: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String]?
        var code: [String]?

        func add(_ kind: MarkdownBlock.Kind, _ text: String) {
            blocks.append(MarkdownBlock(id: blocks.count, kind: kind, text: text))
        }
        func flush() {
            if let lines = paragraph { add(.paragraph, lines.joined(separator: " ")) }
            paragraph = nil
        }

        for (index, line) in source.components(separatedBy: "\n").enumerated() {
            if var lines = code {
                if line.hasPrefix("```") {
                    add(.code, lines.joined(separator: "\n"))
                    code = nil
                } else {
                    lines.append(line)
                    code = lines
                }
                continue
            }
            if line.hasPrefix("```") { flush(); code = []; continue }
            if line.trimmingCharacters(in: .whitespaces).isEmpty { flush(); continue }

            if let m = match(#"^###\s+(.*)"#, line) {
                flush(); add(.heading3, m[0])
            } else if let m = match(#"^#{1,2}\s+(.*)"#, line) {
                flush(); add(.heading2, m[0])
            } else if let m = match(#"^\s*[-*]\s+\[([ xX])\]\s+(.*)"#, line) {
                flush(); add(.checklist(checked: m[0] != " ", line: index), m[1])
            } else if let m = match(#"^\s*[-*]\s+(.*)"#, line) {
                flush(); add(.bullet, m[0])
            } else if let m = match(#"^>\s?(.*)"#, line) {
                flush(); add(.quote, m[0])
            } else {
                paragraph = (paragraph ?? []) + [line.trimmingCharacters(in: .whitespaces)]
            }
        }
        if let lines = code { add(.code, lines.joined(separator: "\n")) }
        flush()
        return blocks
    }

    /// Capture groups of the first match, or nil
    private static func match(_ pattern: String, _ line: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let result = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line))
        else { return nil }
        return (1..<result.numberOfRanges).map { i in
            Range(result.range(at: i), in: line).map { String(line[$0]) } ?? ""
        }
    }

    /// Inline runs (**bold**, *italic*, `code`, [link](https://…)) as an AttributedString styled for the preview.
    /// Only http(s) links stay clickable.
    static func inline(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        guard var result = try? AttributedString(markdown: text, options: options) else {
            return AttributedString(text)
        }
        for run in result.runs {
            if let intent = run.inlinePresentationIntent, intent.contains(.code) {
                result[run.range].font = Focus.mono
                result[run.range].backgroundColor = Focus.sidebar
            }
            if let url = run.link {
                if let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" {
                    result[run.range].foregroundColor = Focus.liveText
                    result[run.range].underlineStyle = .single
                } else {
                    result[run.range].link = nil
                }
            }
        }
        return result
    }
}

/// The Write-mode toolbar edits. Ranges are UTF-16 (NSString/NSTextView) ranges.
enum MarkdownEdit {
    enum Action: CaseIterable {
        case heading, bold, italic, code, link, bullet, checklist, quote
    }

    /// A minimal replacement: put `replacement` at `range`, then select `selection`.
    struct Change: Equatable {
        let range: NSRange
        let replacement: String
        let selection: NSRange
    }

    static func change(for action: Action, in text: String, selection: NSRange) -> Change {
        switch action {
        case .bold: return wrap(text, selection, "**", "**", placeholder: "bold")
        case .italic: return wrap(text, selection, "*", "*", placeholder: "italic")
        case .code: return wrap(text, selection, "`", "`", placeholder: "code")
        case .link: return wrap(text, selection, "[", "](https://)", placeholder: "link")
        case .heading: return prefixLines(text, selection, "## ")
        case .bullet: return prefixLines(text, selection, "- ")
        case .checklist: return prefixLines(text, selection, "- [ ] ")
        case .quote: return prefixLines(text, selection, "> ")
        }
    }

    /// Applies a change to a string (used by tests and as a fallback without a text view)
    static func apply(_ change: Change, to text: String) -> String {
        (text as NSString).replacingCharacters(in: change.range, with: change.replacement)
    }

    /// Wraps the selection (or a selected placeholder) in `pre`…`post`.
    private static func wrap(_ text: String, _ selection: NSRange, _ pre: String, _ post: String, placeholder: String) -> Change {
        let ns = text as NSString
        let range = clamp(selection, ns.length)
        let inner = range.length > 0 ? ns.substring(with: range) : placeholder
        return Change(
            range: range,
            replacement: pre + inner + post,
            selection: NSRange(location: range.location + (pre as NSString).length, length: (inner as NSString).length)
        )
    }

    /// Adds `prefix` to each selected line, or removes it when every non-empty line already has it.
    private static func prefixLines(_ text: String, _ selection: NSRange, _ prefix: String) -> Change {
        let ns = text as NSString
        let range = clamp(selection, ns.length)
        var lineRange = ns.lineRange(for: range)
        // Leave the trailing newline alone
        if lineRange.length > 0, ns.substring(with: NSRange(location: NSMaxRange(lineRange) - 1, length: 1)) == "\n" {
            lineRange.length -= 1
        }
        let lines = ns.substring(with: lineRange).components(separatedBy: "\n")
        let filled = lines.filter { !$0.isEmpty }
        let removing = !filled.isEmpty && filled.allSatisfy { $0.hasPrefix(prefix) }
        let newLines = lines.map { line -> String in
            if removing { return line.hasPrefix(prefix) ? String(line.dropFirst(prefix.count)) : line }
            return lines.count > 1 && line.isEmpty ? line : prefix + line
        }
        let replacement = newLines.joined(separator: "\n")
        let newSelection: NSRange
        if range.length == 0 {
            // Keep the caret on the same character
            let delta = (newLines[0] as NSString).length - (lines[0] as NSString).length
            newSelection = NSRange(location: max(lineRange.location, range.location + delta), length: 0)
        } else {
            newSelection = NSRange(location: lineRange.location, length: (replacement as NSString).length)
        }
        return Change(range: lineRange, replacement: replacement, selection: newSelection)
    }

    private static func clamp(_ range: NSRange, _ length: Int) -> NSRange {
        let location = min(max(0, range.location), length)
        return NSRange(location: location, length: min(max(0, range.length), length - location))
    }
}
