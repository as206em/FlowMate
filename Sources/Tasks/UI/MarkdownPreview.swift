import SwiftUI

/// Renders a task description: headings, paragraphs, lists, togglable checklists, quotes and code blocks.
struct MarkdownPreview: View {
    let markdown: String
    /// Called with the 0-based source line of a clicked checklist item
    let toggleLine: (Int) -> Void

    private static let size: CGFloat = 14.5
    private static let lineSpacing: CGFloat = 6

    var body: some View {
        let blocks = MarkdownBlocks.parse(markdown)
        VStack(alignment: .leading, spacing: 0) {
            if blocks.isEmpty {
                Text("No description yet. Click Write to add one.")
                    .font(.system(size: Self.size))
                    .foregroundColor(Focus.text3)
                    .padding(.vertical, 6)
            }
            ForEach(blocks) { block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func blockView(_ block: MarkdownBlock) -> some View {
        switch block.kind {
        case .heading2:
            inline(block.text, font: .system(size: 17, weight: .semibold))
                .padding(.top, 14).padding(.bottom, 4)
        case .heading3:
            inline(block.text, font: .system(size: 15, weight: .semibold))
                .padding(.top, 12).padding(.bottom, 2)
        case .paragraph:
            inline(block.text)
                .padding(.vertical, 6)
        case .bullet:
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Circle().fill(Focus.text3).frame(width: 5, height: 5)
                    .alignmentGuide(.firstTextBaseline) { d in d[.bottom] + 1.5 }
                inline(block.text)
            }
            .padding(.vertical, 3)
        case let .checklist(checked, line):
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Button { toggleLine(line) } label: {
                    ChecklistBox(checked: checked, size: 15, radius: 4)
                }
                .buttonStyle(.plain)
                .alignmentGuide(.firstTextBaseline) { d in d[.bottom] - 3 }
                .accessibilityLabel(checked ? "Uncheck item" : "Check item")
                inline(block.text, color: checked ? Focus.text3 : Focus.text)
                    .strikethrough(checked, color: Focus.text3)
            }
            .padding(.vertical, 3)
        case .quote:
            inline(block.text, color: Focus.text2)
                .padding(.vertical, 2)
                .padding(.leading, 14)
                .overlay(alignment: .leading) { Rectangle().fill(Focus.lineStrong).frame(width: 3) }
                .padding(.vertical, 8)
        case .code:
            Text(block.text)
                .font(.system(size: 12.5, design: .monospaced))
                .lineSpacing(3)
                .foregroundColor(Focus.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12).padding(.horizontal, 14)
                .background(RoundedRectangle(cornerRadius: 8).fill(Focus.sidebar))
                .padding(.vertical, 8)
        }
    }

    private func inline(_ text: String, font: Font = .system(size: size), color: Color = Focus.text) -> some View {
        Text(MarkdownBlocks.inline(text))
            .font(font)
            .lineSpacing(Self.lineSpacing)
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Square checkbox: done-purple with a white check when on. Used by checklists and subtasks.
struct ChecklistBox: View {
    let checked: Bool
    var size: CGFloat = 16
    var radius: CGFloat = 5

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: radius)
                .fill(checked ? Focus.done : Color.clear)
            RoundedRectangle(cornerRadius: radius)
                .strokeBorder(checked ? Focus.done : Focus.text3, lineWidth: 1.5)
            if checked {
                Image(systemName: "checkmark")
                    .font(.system(size: size * 0.58, weight: .heavy))
                    .foregroundColor(.white)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Rectangle())
    }
}
