import SwiftUI
import AppKit

/// Lets the toolbar reach the editor's text view to edit at the selection.
@MainActor
final class MarkdownEditorProxy {
    fileprivate weak var textView: NSTextView?

    /// Applies a toolbar edit at the current selection, undoable, and keeps the editor focused.
    func apply(_ action: MarkdownEdit.Action) {
        guard let textView else { return }
        let change = MarkdownEdit.change(for: action, in: textView.string, selection: textView.selectedRange())
        textView.window?.makeFirstResponder(textView)
        if textView.shouldChangeText(in: change.range, replacementString: change.replacement) {
            textView.textStorage?.replaceCharacters(in: change.range, with: change.replacement)
            textView.didChangeText()
        }
        textView.setSelectedRange(change.selection)
        textView.scrollRangeToVisible(change.selection)
    }

    func focus() {
        guard let textView else { return }
        textView.window?.makeFirstResponder(textView)
    }
}

/// Monospaced Markdown editor (NSTextView) that grows with its text; the panel's scroll view does the scrolling.
struct MarkdownEditor: NSViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    /// Height the text needs; the caller frames the editor with it
    @Binding var height: CGFloat
    let placeholder: String
    let proxy: MarkdownEditorProxy
    /// Esc inside the editor
    var onEscape: () -> Void = {}

    static let font = NSFont.monospacedSystemFont(ofSize: 13.5, weight: .regular)

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> EditorTextView {
        let textView = EditorTextView()
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.importsGraphics = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.drawsBackground = false
        textView.textColor = NSColor(hex: 0x18181B)
        textView.insertionPointColor = NSColor(hex: 0x18181B)
        textView.font = Self.font
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        paragraph.maximumLineHeight = 22
        textView.defaultParagraphStyle = paragraph
        textView.typingAttributes = [.font: Self.font, .paragraphStyle: paragraph, .foregroundColor: NSColor(hex: 0x18181B)]
        textView.textContainerInset = NSSize(width: 15, height: 14)
        textView.isVerticallyResizable = false
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.placeholder = placeholder
        textView.onEscape = onEscape
        textView.onLayout = { [weak coordinator = context.coordinator] in coordinator?.measure() }
        textView.string = text
        textView.setAccessibilityLabel("Description (Markdown)")
        proxy.textView = textView
        context.coordinator.textView = textView
        return textView
    }

    func updateNSView(_ textView: EditorTextView, context: Context) {
        context.coordinator.parent = self
        proxy.textView = textView
        textView.placeholder = placeholder
        textView.onEscape = onEscape
        // Only push outside changes (e.g. a checklist toggled elsewhere); typing already matches.
        if textView.string != text {
            let selection = textView.selectedRange()
            textView.string = text
            let length = (text as NSString).length
            textView.setSelectedRange(NSRange(location: min(selection.location, length), length: 0))
        }
    }

    @MainActor
    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: MarkdownEditor
        weak var textView: EditorTextView?

        init(_ parent: MarkdownEditor) { self.parent = parent }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            parent.text = textView.string
            measure()
        }

        func textDidBeginEditing(_ notification: Notification) { parent.isFocused = true }
        func textDidEndEditing(_ notification: Notification) { parent.isFocused = false }

        /// Reports the text's height so SwiftUI can resize the editor.
        func measure() {
            guard let textView, textView.bounds.width > 0 else { return }
            let height = textView.contentHeight(forWidth: textView.bounds.width)
            guard abs(height - parent.height) > 0.5 else { return }
            // Not during a SwiftUI update pass
            DispatchQueue.main.async { [parent] in parent.height = height }
        }
    }
}

/// NSTextView with a placeholder, an Esc hook and a content-height measure.
final class EditorTextView: NSTextView {
    var placeholder = ""
    var onEscape: () -> Void = {}
    var onLayout: () -> Void = {}

    /// Height of the laid-out text plus insets at a given width
    func contentHeight(forWidth width: CGFloat) -> CGFloat {
        guard let container = textContainer, let layout = layoutManager else { return 0 }
        let inner = max(10, width - textContainerInset.width * 2)
        if abs(container.size.width - inner) > 0.5 {
            container.size = NSSize(width: inner, height: .greatestFiniteMagnitude)
        }
        layout.ensureLayout(for: container)
        var used = layout.usedRect(for: container).height
        // An empty last line after a newline isn't in usedRect; count it so the caret stays visible
        used = max(used, layout.extraLineFragmentRect.maxY)
        return ceil(used + textContainerInset.height + 18)
    }

    override func setFrameSize(_ newSize: NSSize) {
        let widthChanged = abs(newSize.width - frame.width) > 0.5
        super.setFrameSize(newSize)
        if widthChanged { onLayout() }
    }

    override func cancelOperation(_ sender: Any?) {
        onEscape()
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard string.isEmpty, !placeholder.isEmpty else { return }
        let padding = textContainer?.lineFragmentPadding ?? 5
        let rect = NSRect(
            x: textContainerInset.width + padding,
            y: textContainerInset.height,
            width: bounds.width - (textContainerInset.width + padding) * 2,
            height: bounds.height - textContainerInset.height * 2
        )
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = 22
        (placeholder as NSString).draw(in: rect, withAttributes: [
            .font: MarkdownEditor.font,
            .foregroundColor: NSColor(hex: 0x6E6E78),
            .paragraphStyle: paragraph,
        ])
    }
}
