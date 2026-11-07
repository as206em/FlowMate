import XCTest
@testable import FlowMate

final class MarkdownTextTests: XCTestCase {

    // MARK: - Blocks

    func testParsesBlockKinds() {
        let source = """
        ## Plan
        ### Details
        First line
        continues here

        - bullet
        - [ ] open item
        - [x] done item
        > quoted
        ```
        let x = 1
        ```
        """
        let kinds = MarkdownBlocks.parse(source).map(\.kind)
        XCTAssertEqual(kinds, [
            .heading2, .heading3, .paragraph, .bullet,
            .checklist(checked: false, line: 6), .checklist(checked: true, line: 7),
            .quote, .code,
        ])
        let blocks = MarkdownBlocks.parse(source)
        XCTAssertEqual(blocks[2].text, "First line continues here")
        XCTAssertEqual(blocks[5].text, "done item")
        XCTAssertEqual(blocks[7].text, "let x = 1")
    }

    func testEmptyAndUnclosedCode() {
        XCTAssertTrue(MarkdownBlocks.parse("").isEmpty)
        XCTAssertTrue(MarkdownBlocks.parse("\n  \n").isEmpty)
        let blocks = MarkdownBlocks.parse("```\nopen")
        XCTAssertEqual(blocks.map(\.kind), [.code])
        XCTAssertEqual(blocks.first?.text, "open")
    }

    func testBoldLineIsNotABullet() {
        XCTAssertEqual(MarkdownBlocks.parse("**bold** start").map(\.kind), [.paragraph])
        XCTAssertEqual(MarkdownBlocks.parse("* star bullet").map(\.kind), [.bullet])
    }

    func testChecklistLineMatchesStoreToggle() {
        let source = "Intro\n\n- [ ] ship it"
        guard case let .checklist(_, line)? = MarkdownBlocks.parse(source).last?.kind else {
            return XCTFail("expected a checklist")
        }
        XCTAssertEqual(MarkdownChecklist.toggling(line: line, in: source), "Intro\n\n- [x] ship it")
    }

    func testInlineKeepsOnlyWebLinks() {
        let web = MarkdownBlocks.inline("see [docs](https://example.com)")
        XCTAssertEqual(String(web.characters), "see docs")
        XCTAssertTrue(web.runs.contains { $0.link?.absoluteString == "https://example.com" })

        let local = MarkdownBlocks.inline("[x](file:///etc/hosts)")
        XCTAssertFalse(local.runs.contains { $0.link != nil })
    }

    // MARK: - Toolbar edits

    private func edit(_ action: MarkdownEdit.Action, _ text: String, _ location: Int, _ length: Int = 0) -> (String, NSRange) {
        let change = MarkdownEdit.change(for: action, in: text, selection: NSRange(location: location, length: length))
        return (MarkdownEdit.apply(change, to: text), change.selection)
    }

    func testWrapSelection() {
        let (text, selection) = edit(.bold, "make this loud", 5, 4)
        XCTAssertEqual(text, "make **this** loud")
        XCTAssertEqual(selection, NSRange(location: 7, length: 4))
    }

    func testWrapInsertsSelectedPlaceholder() {
        let (text, selection) = edit(.link, "go ", 3)
        XCTAssertEqual(text, "go [link](https://)")
        XCTAssertEqual(selection, NSRange(location: 4, length: 4))
    }

    func testLinePrefixAtCaretAndToggleOff() {
        let (text, selection) = edit(.checklist, "one\ntwo", 5)
        XCTAssertEqual(text, "one\n- [ ] two")
        XCTAssertEqual(selection.location, 11)

        let (back, _) = edit(.checklist, text, 11)
        XCTAssertEqual(back, "one\ntwo")
    }

    func testLinePrefixOnSeveralLines() {
        let (text, _) = edit(.quote, "a\nb\nc", 0, 3)
        XCTAssertEqual(text, "> a\n> b\nc")
    }

    func testHeadingOnEmptyText() {
        let (text, selection) = edit(.heading, "", 0)
        XCTAssertEqual(text, "## ")
        XCTAssertEqual(selection, NSRange(location: 3, length: 0))
    }
}
