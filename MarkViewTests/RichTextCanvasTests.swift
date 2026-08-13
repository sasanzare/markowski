import XCTest
import AppKit
import SwiftUI
@testable import MarkView

/// The canvas edits an `NSAttributedString`, so the projection into it and back
/// out of it has to be an exact identity. If it isn't, typing silently rewrites
/// parts of the document the user never touched.
final class RichTextCanvasTests: XCTestCase {

    private func assertProjectionIsIdentity(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let document = MarkdownDocumentParser.parse(markdown)
        let attributed = RichTextRenderer.attributedString(for: document)
        let recovered = RichTextReader.document(from: attributed)

        XCTAssertTrue(
            document.hasSameContent(as: recovered),
            """
            model → attributed → model was not an identity.
            source:    \(markdown.debugDescription)
            rendered:  \(attributed.string.debugDescription)
            expected:  \(document.blocks.map(\.content))
            actual:    \(recovered.blocks.map(\.content))
            """,
            file: file, line: line
        )
    }

    // MARK: - Projection identity

    func testProjectionIsIdentityForEveryBlockKind() {
        assertProjectionIsIdentity("# Title\n\nA paragraph.")
        assertProjectionIsIdentity("Plain body text.")
        assertProjectionIsIdentity("## Second level\n\n### Third level")
        assertProjectionIsIdentity("- one\n- two\n- three")
        assertProjectionIsIdentity("1. first\n2. second")
        assertProjectionIsIdentity("- [ ] todo\n- [x] done\n- plain")
        assertProjectionIsIdentity("> quoted line")
        assertProjectionIsIdentity("```swift\nlet x = 1\nlet y = 2\n```")
        assertProjectionIsIdentity("| A | B |\n| --- | :---: |\n| 1 | 2 |")
        assertProjectionIsIdentity("---")
        assertProjectionIsIdentity("<div dir=\"rtl\" markdown=\"1\">\nx\n</div>")
    }

    func testProjectionKeepsInlineStyles() {
        assertProjectionIsIdentity("Text with **bold** and *italic* and `code` and ~~struck~~.")
        assertProjectionIsIdentity("A [link](https://example.com) inside.")
        assertProjectionIsIdentity("Mixed ***bold italic*** run.")
    }

    func testProjectionIsIdentityForARealisticDocument() {
        assertProjectionIsIdentity("""
        # Project README

        One sentence with **bold** and a [link](https://example.com).

        ## Installation

        ```bash
        brew install thing
        ```

        - First point
        - Second with `code`
        - [x] Done

        > An aside.

        | Option | Default |
        | :--- | ---: |
        | `--fast` | off |

        ---

        Final paragraph.
        """)
    }

    func testProjectionIsIdentityForPersianText() {
        assertProjectionIsIdentity("""
        # عنوان سند

        متن فارسی با **پررنگ** در میان.

        - مورد اول
        - مورد دوم
        """)
    }

    /// The visible text must contain no Markdown syntax at all — that is the
    /// entire point of the canvas.
    func testRenderedTextContainsNoMarkdownSyntax() {
        let document = MarkdownDocumentParser.parse("""
        # Title

        Some **bold** and *italic* and a [link](https://example.com).

        - an item
        """)
        let text = RichTextRenderer.attributedString(for: document).string

        XCTAssertFalse(text.contains("#"), "Heading syntax leaked into the canvas")
        XCTAssertFalse(text.contains("**"), "Bold syntax leaked into the canvas")
        XCTAssertFalse(text.contains("]("), "Link syntax leaked into the canvas")
        XCTAssertTrue(text.contains("Title"))
        XCTAssertTrue(text.contains("bold"))
        XCTAssertTrue(text.contains("link"), "The link's label is the text; its URL is an attribute")
        XCTAssertTrue(text.contains("•"), "A bullet is drawn as a marker, not typed as '-'")
    }

    // MARK: - Typography

    func testHeadingsAreLargerAndBolderThanBody() throws {
        let document = MarkdownDocumentParser.parse("# Heading\n\nBody text.")
        let attributed = RichTextRenderer.attributedString(for: document)

        let headingFont = try XCTUnwrap(attributed.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
        let bodyLocation = (attributed.string as NSString).range(of: "Body").location
        let bodyFont = try XCTUnwrap(attributed.attribute(.font, at: bodyLocation, effectiveRange: nil) as? NSFont)

        XCTAssertGreaterThan(headingFont.pointSize, bodyFont.pointSize)
        XCTAssertTrue(NSFontManager.shared.traits(of: headingFont).contains(.boldFontMask))
        XCTAssertFalse(NSFontManager.shared.traits(of: bodyFont).contains(.boldFontMask))
    }

    func testPersianParagraphsGetRightToLeftLayout() throws {
        let document = MarkdownDocumentParser.parse("English line.\n\nمتن فارسی است.")
        let attributed = RichTextRenderer.attributedString(for: document)

        let englishStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle
        )
        let persianLocation = (attributed.string as NSString).range(of: "متن").location
        let persianStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: persianLocation, effectiveRange: nil) as? NSParagraphStyle
        )

        XCTAssertEqual(englishStyle.baseWritingDirection, .leftToRight)
        XCTAssertEqual(englishStyle.alignment, .left)
        // Direction is decided per paragraph by its own text, so a Persian
        // paragraph inside an English document lays out correctly on its own.
        XCTAssertEqual(persianStyle.baseWritingDirection, .rightToLeft)
        XCTAssertEqual(persianStyle.alignment, .right)
    }

    func testNestedListItemsIndentFurther() throws {
        let document = MarkdownDocumentParser.parse("- top\n  - nested")
        let attributed = RichTextRenderer.attributedString(for: document)

        let topLocation = (attributed.string as NSString).range(of: "top").location
        let nestedLocation = (attributed.string as NSString).range(of: "nested").location

        let topStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: topLocation, effectiveRange: nil) as? NSParagraphStyle
        )
        let nestedStyle = try XCTUnwrap(
            attributed.attribute(.paragraphStyle, at: nestedLocation, effectiveRange: nil) as? NSParagraphStyle
        )
        XCTAssertGreaterThan(nestedStyle.headIndent, topStyle.headIndent)
    }

    func testOrderedMarkersCountUpAndCheckboxesShowState() {
        let document = MarkdownDocumentParser.parse("3. a\n4. b")
        let text = RichTextRenderer.attributedString(for: document).string
        XCTAssertTrue(text.contains("3."), "An ordered list keeps the number it started at")
        XCTAssertTrue(text.contains("4."))

        let tasks = MarkdownDocumentParser.parse("- [ ] open\n- [x] closed")
        let taskText = RichTextRenderer.attributedString(for: tasks).string
        XCTAssertTrue(taskText.contains("☐"))
        XCTAssertTrue(taskText.contains("☑"))
    }

    // MARK: - Structure carried in attributes

    func testEveryParagraphCarriesItsBlockIdentity() throws {
        let document = MarkdownDocumentParser.parse("# Title\n\nBody\n\n- item")
        let attributed = RichTextRenderer.attributedString(for: document)

        let headingDescriptor = try XCTUnwrap(attributed.paragraphDescriptor(at: 0))
        XCTAssertEqual(headingDescriptor.blockID, document.blocks[0].id)

        let bodyLocation = (attributed.string as NSString).range(of: "Body").location
        let bodyDescriptor = try XCTUnwrap(attributed.paragraphDescriptor(at: bodyLocation))
        XCTAssertEqual(bodyDescriptor.blockID, document.blocks[1].id)
        XCTAssertEqual(bodyDescriptor.role, .paragraph)
    }

    func testBlockIdentitySurvivesTheRoundTrip() {
        let document = MarkdownDocumentParser.parse("# Title\n\nBody")
        let attributed = RichTextRenderer.attributedString(for: document)
        let recovered = RichTextReader.document(from: attributed)

        // Identity is what the assistant and undo address blocks by, so it has
        // to come back, not be regenerated.
        XCTAssertEqual(recovered.blocks.map(\.id), document.blocks.map(\.id))
    }

    // MARK: - Editing the storage directly

    func testEditingOneParagraphLeavesEveryOtherBlockIdentical() {
        let document = MarkdownDocumentParser.parse("# Title\n\nFirst.\n\nSecond.")
        let storage = NSTextStorage(attributedString: RichTextRenderer.attributedString(for: document))

        // Type into the middle paragraph, the way a text view would.
        let range = (storage.string as NSString).range(of: "First.")
        storage.replaceCharacters(in: range, with: "First, edited.")

        let recovered = RichTextReader.document(from: storage)
        XCTAssertEqual(recovered.blocks.count, 3)
        XCTAssertEqual(recovered.blocks[1].plainText, "First, edited.")
        XCTAssertEqual(recovered.blocks[0], document.blocks[0])
        XCTAssertEqual(recovered.blocks[2], document.blocks[2])
        XCTAssertEqual(recovered.blocks[0].id, document.blocks[0].id)
    }

    func testTypingIntoAnEmptyDocumentProducesABodyParagraph() {
        let storage = NSTextStorage(attributedString: NSAttributedString(string: "Hello"))
        let recovered = RichTextReader.document(from: storage)

        XCTAssertEqual(recovered.blocks.count, 1)
        guard case .paragraph(let text) = recovered.blocks[0].content else {
            return XCTFail("Text with no descriptor must become body text")
        }
        XCTAssertEqual(text.plainText, "Hello")
    }

    func testEditedCanvasStillSerialisesToValidMarkdown() {
        let document = MarkdownDocumentParser.parse("# Title\n\n- one\n- two")
        let storage = NSTextStorage(attributedString: RichTextRenderer.attributedString(for: document))

        let range = (storage.string as NSString).range(of: "two")
        storage.replaceCharacters(in: range, with: "two edited")

        let markdown = MarkdownDocumentSerializer.serialize(RichTextReader.document(from: storage))
        XCTAssertTrue(markdown.contains("# Title"))
        XCTAssertTrue(markdown.contains("- one"))
        XCTAssertTrue(markdown.contains("- two edited"))

        // And that Markdown still parses to the same document.
        let reparsed = MarkdownDocumentParser.parse(markdown)
        XCTAssertTrue(reparsed.hasSameContent(as: RichTextReader.document(from: storage)))
    }

    // MARK: - Tables as objects

    private func tableAttachment(in attributed: NSAttributedString) -> TableAttachment? {
        var found: TableAttachment?
        attributed.enumerateAttribute(.attachment, in: attributed.fullRange, options: []) { value, _, stop in
            if let attachment = value as? TableAttachment {
                found = attachment
                stop.pointee = true
            }
        }
        return found
    }

    func testTableIsAnObjectNotRowsOfText() throws {
        let document = MarkdownDocumentParser.parse("| A | B |\n| --- | :---: |\n| 1 | 2 |")
        let attributed = RichTextRenderer.attributedString(for: document)

        // The whole table occupies one attachment character.
        XCTAssertFalse(attributed.string.contains("|"), "Pipe syntax must never appear in the canvas")
        XCTAssertFalse(attributed.string.contains("\t"), "Cells are objects now, not tab-separated text")
        XCTAssertEqual(attributed.string.count, 1, "A table is one attachment, not a run of rows")

        let attachment = try XCTUnwrap(tableAttachment(in: attributed))
        XCTAssertEqual(attachment.table.columnCount, 2)
        XCTAssertEqual(attachment.table.alignments, [.none, .center])
        XCTAssertEqual(attachment.table.header.cells.map(\.content.plainText), ["A", "B"])
        XCTAssertEqual(attachment.blockID, document.blocks[0].id)
    }

    @MainActor
    func testEditingACellMutatesTheModelNotCharacters() throws {
        let document = MarkdownDocumentParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let attributed = RichTextRenderer.attributedString(for: document)
        let attachment = try XCTUnwrap(tableAttachment(in: attributed))

        let grid = DocumentTableView(
            table: attachment.table,
            blockID: attachment.blockID,
            theme: .standard
        )
        grid.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        grid.layoutSubtreeIfNeeded()

        var reported: TableBlock?
        grid.onChange = { _, table in reported = table }

        // Type into the cell holding "2".
        let cell = try XCTUnwrap(findCell(in: grid, containing: "2"))
        cell.string = "changed"
        cell.didChangeText()

        let table = try XCTUnwrap(reported)
        XCTAssertEqual(table.rows[0].cells[1].content.plainText, "changed")
        XCTAssertEqual(table.rows[0].cells[0].content.plainText, "1", "The neighbouring cell is untouched")
        XCTAssertEqual(table.columnCount, 2, "Editing text must not change the shape")
    }

    @MainActor
    func testStructuralEditsMutateTheTable() throws {
        let document = MarkdownDocumentParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let attachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: document)))
        let grid = DocumentTableView(table: attachment.table, blockID: attachment.blockID, theme: .standard)
        grid.frame = NSRect(x: 0, y: 0, width: 600, height: 200)

        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        grid.insertRow(at: 1)
        XCTAssertEqual(try XCTUnwrap(latest).rows.count, 2)

        grid.insertColumn(at: 2)
        XCTAssertEqual(try XCTUnwrap(latest).columnCount, 3)
        XCTAssertTrue(
            ([latest!.header] + latest!.rows).allSatisfy { $0.cells.count == 3 },
            "Every row keeps the table's width"
        )

        grid.deleteColumn(at: 2)
        XCTAssertEqual(try XCTUnwrap(latest).columnCount, 2)

        grid.deleteRow(at: 1)
        XCTAssertEqual(try XCTUnwrap(latest).rows.count, 1)

        // The header row is not deletable — a table without one isn't a table.
        grid.deleteRow(at: 0)
        XCTAssertEqual(try XCTUnwrap(latest).rows.count, 1)
        XCTAssertEqual(latest!.header.cells.map(\.content.plainText), ["A", "B"])
    }

    @MainActor
    func testAlignmentAndRightToLeftDetection() throws {
        let document = MarkdownDocumentParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let attachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: document)))
        let grid = DocumentTableView(table: attachment.table, blockID: attachment.blockID, theme: .standard)

        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        grid.setAlignment(.right, forColumn: 1)
        XCTAssertEqual(try XCTUnwrap(latest).alignments, [.none, .right])
        XCTAssertFalse(grid.isRightToLeft)

        let persian = MarkdownDocumentParser.parse("| ستون | مقدار |\n| --- | --- |\n| یک | دو |")
        let persianAttachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: persian)))
        let persianGrid = DocumentTableView(
            table: persianAttachment.table, blockID: persianAttachment.blockID, theme: .standard
        )
        XCTAssertTrue(persianGrid.isRightToLeft, "A Persian table lays its columns out right to left")
    }

    @MainActor
    func testTabFromTheLastCellGrowsTheTable() throws {
        let document = MarkdownDocumentParser.parse("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let attachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: document)))
        let grid = DocumentTableView(table: attachment.table, blockID: attachment.blockID, theme: .standard)
        grid.frame = NSRect(x: 0, y: 0, width: 600, height: 200)
        grid.layoutSubtreeIfNeeded()

        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        // Tab out of the very last cell, the way a spreadsheet adds a row.
        let lastCell = try XCTUnwrap(findCell(in: grid, containing: "2"))
        lastCell.insertTab(nil)

        XCTAssertEqual(try XCTUnwrap(latest).rows.count, 2, "Tabbing off the end adds a row")
    }

    @MainActor
    func testGridLaysOutWithRealCellFrames() throws {
        let document = MarkdownDocumentParser.parse("| Name | A much longer column heading |\n| --- | --- |\n| x | y |")
        let attachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: document)))
        let grid = DocumentTableView(table: attachment.table, blockID: attachment.blockID, theme: .standard)
        grid.frame = NSRect(x: 0, y: 0, width: 620, height: 0)
        grid.frame.size.height = grid.measuredHeight(for: 620)
        grid.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(grid.measuredHeight(for: 620), 40, "The grid measured to nothing")

        let cells = collectCells(in: grid)
        XCTAssertEqual(cells.count, 4, "Two columns across two rows")
        XCTAssertTrue(cells.allSatisfy { $0.frame.width > 0 && $0.frame.height > 0 })

        // Columns share the width by how much text they hold, so the long
        // heading gets more room than "Name".
        let header = cells.filter { $0.frame.minY < 30 }.sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertEqual(header.count, 2)
        XCTAssertGreaterThan(header[1].frame.width, header[0].frame.width)
    }

    @MainActor
    private func collectCells(in view: NSView) -> [TableCellTextView] {
        var found: [TableCellTextView] = []
        func search(_ view: NSView) {
            if let cell = view as? TableCellTextView { found.append(cell) }
            view.subviews.forEach(search)
        }
        search(view)
        return found
    }

    @MainActor
    private func findCell(in view: NSView, containing text: String) -> TableCellTextView? {
        collectCells(in: view).first { $0.string == text }
    }

    // MARK: - The live canvas

    /// Builds a real, laid-out canvas the way SwiftUI would, so these exercise
    /// the actual view rather than the bridge in isolation.
    @MainActor
    private func makeCanvas(_ markdown: String) -> (NSHostingView<RichTextCanvas>, CanvasTextView, Binding<String>) {
        var storage = markdown
        let binding = Binding<String>(get: { storage }, set: { storage = $0 })

        let hosting = NSHostingView(rootView: RichTextCanvas(markdown: binding))
        hosting.frame = NSRect(x: 0, y: 0, width: 900, height: 700)
        hosting.layoutSubtreeIfNeeded()

        var found: CanvasTextView?
        func search(_ view: NSView) {
            if let canvas = view as? CanvasTextView { found = canvas }
            view.subviews.forEach(search)
        }
        search(hosting)

        return (hosting, found!, binding)
    }

    @MainActor
    func testCanvasUsesTextKit2() {
        let (_, textView, _) = makeCanvas("# Title\n\nBody.")
        XCTAssertNotNil(
            textView.textLayoutManager,
            "TextKit 2 is what buys the modern layout path; falling back to TextKit 1 is silent"
        )
        XCTAssertTrue(textView.isEditable)
        XCTAssertTrue(textView.allowsUndo)
    }

    @MainActor
    func testCanvasShowsTheDocumentWithoutMarkdownSyntax() {
        let (_, textView, _) = makeCanvas("# Title\n\nSome **bold** text.\n\n- an item")
        let visible = textView.string

        XCTAssertTrue(visible.contains("Title"))
        XCTAssertTrue(visible.contains("bold"))
        XCTAssertFalse(visible.contains("#"))
        XCTAssertFalse(visible.contains("**"))
        XCTAssertTrue(visible.contains("•"))
    }

    @MainActor
    func testTypingUpdatesTheBoundMarkdownAndNothingElse() {
        let (_, textView, binding) = makeCanvas("# Title\n\nFirst.\n\nSecond.")

        let range = (textView.string as NSString).range(of: "First.")
        textView.setSelectedRange(range)
        textView.insertText("First, edited.", replacementRange: range)

        let markdown = binding.wrappedValue
        XCTAssertTrue(markdown.contains("# Title"), "The heading must survive editing a different block")
        XCTAssertTrue(markdown.contains("First, edited."))
        XCTAssertTrue(markdown.contains("Second."))
        XCTAssertFalse(markdown.contains("First."), "The old text is gone")
    }

    @MainActor
    func testTypingDoesNotReprojectAndSoDoesNotMoveTheCaret() {
        let (hosting, textView, binding) = makeCanvas("A paragraph here.")

        let caret = 5
        textView.setSelectedRange(NSRange(location: caret, length: 0))
        textView.insertText("X", replacementRange: NSRange(location: caret, length: 0))

        // SwiftUI will re-run updateNSView after the binding changes; that must
        // not rebuild the storage, or the caret would jump on every keystroke.
        hosting.layoutSubtreeIfNeeded()

        XCTAssertEqual(textView.selectedRange().location, caret + 1)
        XCTAssertTrue(binding.wrappedValue.contains("A parXagraph here."))
    }

    @MainActor
    func testInlineStyleCommandChangesBothLookAndMeaning() throws {
        let (_, textView, binding) = makeCanvas("make this bold")

        let range = (textView.string as NSString).range(of: "this")
        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.bold)

        // Looks bold…
        let storage = try XCTUnwrap(textView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(NSFontManager.shared.traits(of: font).contains(.boldFontMask))

        // …and saves as bold.
        XCTAssertTrue(binding.wrappedValue.contains("**this**"), "Got: \(binding.wrappedValue)")

        // Toggling again removes it.
        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.bold)
        XCTAssertFalse(binding.wrappedValue.contains("**"))
    }

    @MainActor
    func testInlineCodeCommandTogglesOnAndOff() throws {
        let (_, textView, binding) = makeCanvas("wrap this in code")

        let range = (textView.string as NSString).range(of: "this")
        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.code)

        let storage = try XCTUnwrap(textView.textStorage)
        let font = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertTrue(font.fontDescriptor.symbolicTraits.contains(.monoSpace))
        XCTAssertTrue(binding.wrappedValue.contains("`this`"), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.code)
        XCTAssertFalse(binding.wrappedValue.contains("`"))
        let restored = try XCTUnwrap(storage.attribute(.font, at: range.location, effectiveRange: nil) as? NSFont)
        XCTAssertFalse(restored.fontDescriptor.symbolicTraits.contains(.monoSpace))
    }

    @MainActor
    func testBoldingAWholeListItemSkipsTheBulletAndStillApplies() {
        let (_, textView, binding) = makeCanvas("- an item")

        // Select the entire line, marker included — what ⌘A or a triple-click
        // produces.
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        textView.toggleInlineStyle(.bold)

        XCTAssertTrue(binding.wrappedValue.contains("**an item**"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.hasPrefix("- "), "The list structure must survive")
    }

    @MainActor
    func testSetHeadingLevelConvertsInPlaceAndKeepsTheSelection() {
        let (_, textView, binding) = makeCanvas("First.\n\nSecond paragraph.\n\nThird.")

        let range = (textView.string as NSString).range(of: "Second")
        textView.setSelectedRange(range)
        XCTAssertTrue(textView.setHeadingLevel(2))

        XCTAssertTrue(binding.wrappedValue.contains("## Second paragraph."), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("First."))
        XCTAssertTrue(binding.wrappedValue.contains("Third."))
        XCTAssertEqual(textView.selectedRange(), range, "The selection must not move")

        // And back to body text.
        XCTAssertTrue(textView.setHeadingLevel(0))
        XCTAssertFalse(binding.wrappedValue.contains("##"))
    }

    @MainActor
    func testSetHeadingLevelRefusesStructuredParagraphs() {
        let (_, textView, binding) = makeCanvas("- a list item")

        let range = (textView.string as NSString).range(of: "list")
        textView.setSelectedRange(range)

        XCTAssertFalse(textView.setHeadingLevel(1), "A list item is not a heading's to take")
        XCTAssertTrue(binding.wrappedValue.contains("- a list item"), "The document must be untouched")
    }

    // MARK: - Tables beyond what Markdown can say

    /// A plain table must keep writing as plain Markdown. Escalating every
    /// table to HTML would make ordinary documents unreadable everywhere else.
    func testOrdinaryTableStaysMarkdown() {
        let document = MarkdownDocumentParser.parse("| A | B |\n| :--- | ---: |\n| 1 | 2 |")
        guard case .table(let table) = document.blocks[0].content else {
            return XCTFail("Expected a table")
        }
        XCTAssertFalse(table.needsHTML)

        let serialized = MarkdownDocumentSerializer.serialize(document)
        XCTAssertTrue(serialized.contains("| :--- | ---: |"), "Got: \(serialized)")
        XCTAssertFalse(serialized.contains("<table"), "Got: \(serialized)")
    }

    private func tableFromMarkdown(_ markdown: String) throws -> TableBlock {
        let document = MarkdownDocumentParser.parse(markdown)
        guard case .table(let table) = document.blocks[0].content else {
            throw XCTSkip("Expected a table")
        }
        return table
    }

    func testMergingCellsEscalatesToHTMLAndRoundTrips() throws {
        var table = try tableFromMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |")

        // Merge the header's two cells into one.
        table.header.cells[0].columnSpan = 2
        table.normalize()

        XCTAssertTrue(table.needsHTML)
        XCTAssertTrue(table.header.cells[1].isCovered, "The covered position is derived, not authored")

        let serialized = MarkdownDocumentSerializer.serialize(
            RichDocument(blocks: [RichBlock(content: .table(table))])
        )
        XCTAssertTrue(serialized.contains("colspan=\"2\""), "Got: \(serialized)")

        let reparsed = try tableFromMarkdown(serialized)
        XCTAssertEqual(reparsed.columnCount, 2)
        XCTAssertEqual(reparsed.header.cells[0].columnSpan, 2)
        XCTAssertTrue(reparsed.header.cells[1].isCovered)
        XCTAssertEqual(reparsed.rows[0].cells.map(\.content.plainText), ["1", "2"])
    }

    func testRowSpanRoundTrips() throws {
        var table = try tableFromMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        table.rows[0].cells[0].rowSpan = 2
        table.normalize()

        let serialized = MarkdownDocumentSerializer.serialize(
            RichDocument(blocks: [RichBlock(content: .table(table))])
        )
        XCTAssertTrue(serialized.contains("rowspan=\"2\""), "Got: \(serialized)")

        let reparsed = try tableFromMarkdown(serialized)
        XCTAssertEqual(reparsed.rows[0].cells[0].rowSpan, 2)
        XCTAssertEqual(reparsed.rows[0].cells[0].content.plainText, "1")
        XCTAssertTrue(reparsed.rows[1].cells[0].isCovered, "The row below is covered by the span")
        XCTAssertEqual(reparsed.rows[1].cells[1].content.plainText, "4")
    }

    func testPerCellAndVerticalAlignmentRoundTrip() throws {
        var table = try tableFromMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |")
        table.rows[0].cells[1].horizontalAlignment = .right
        table.rows[0].cells[1].verticalAlignment = .bottom
        table.normalize()

        let serialized = MarkdownDocumentSerializer.serialize(
            RichDocument(blocks: [RichBlock(content: .table(table))])
        )
        XCTAssertTrue(serialized.contains("valign=\"bottom\""), "Got: \(serialized)")

        let reparsed = try tableFromMarkdown(serialized)
        XCTAssertEqual(reparsed.rows[0].cells[1].horizontalAlignment, .right)
        XCTAssertEqual(reparsed.rows[0].cells[1].verticalAlignment, .bottom)
    }

    func testInlineStylesInsideAnHTMLTableSurvive() throws {
        var table = try tableFromMarkdown("| A | B |\n| --- | --- |\n| **bold** | [x](y) |")
        table.header.cells[0].verticalAlignment = .top
        table.normalize()

        let reparsed = try tableFromMarkdown(
            MarkdownDocumentSerializer.serialize(RichDocument(blocks: [RichBlock(content: .table(table))]))
        )
        let first = reparsed.rows[0].cells[0].content
        XCTAssertTrue(first.runs.contains { $0.style.contains(.bold) }, "Got: \(first.runs)")
        XCTAssertEqual(reparsed.rows[0].cells[1].content.runs.first?.link, "y")
    }

    /// Coverage is recomputed from the spans, so a span that no longer fits is
    /// clipped instead of drawing over cells that are not there.
    func testDeletingARowClipsASpanThatReachedIntoIt() throws {
        var table = try tableFromMarkdown("| A |\n| --- |\n| 1 |\n| 2 |")
        table.rows[0].cells[0].rowSpan = 2
        table.normalize()
        XCTAssertTrue(table.rows[1].cells[0].isCovered)

        table.rows.removeLast()
        table.normalize()

        XCTAssertEqual(table.rows[0].cells[0].rowSpan, 1, "The span must shrink to what still exists")
        XCTAssertFalse(table.needsHTML, "With nothing special left it goes back to plain Markdown")
    }

    func testAnchorFindsTheCellOwningACoveredPosition() throws {
        var table = try tableFromMarkdown("| A | B |\n| --- | --- |\n| 1 | 2 |")
        table.header.cells[0].columnSpan = 2
        table.normalize()

        XCTAssertEqual(table.anchor(forRow: 0, column: 1).map { [$0.row, $0.column] }, [0, 0])
        XCTAssertEqual(table.anchor(forRow: 1, column: 1).map { [$0.row, $0.column] }, [1, 1])
    }

    @MainActor
    func testMergingThroughTheGridKeepsTextAndSavesAsHTML() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| left | right |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        _ = try XCTUnwrap(findCell(in: grid, containing: "left")).becomeFirstResponder()
        XCTAssertTrue(bridge.apply(.mergeRight))

        let merged = try XCTUnwrap(latest)
        XCTAssertEqual(merged.rows[0].cells[0].columnSpan, 2)
        XCTAssertTrue(merged.rows[0].cells[1].isCovered)
        // Text from the absorbed cell is kept rather than thrown away.
        XCTAssertEqual(merged.rows[0].cells[0].content.plainText, "left right")

        let serialized = MarkdownDocumentSerializer.serialize(
            RichDocument(blocks: [RichBlock(content: .table(merged))])
        )
        XCTAssertTrue(serialized.contains("colspan=\"2\""), "Got: \(serialized)")

        // And splitting it again returns the table to plain Markdown.
        XCTAssertTrue(bridge.apply(.unmerge))
        let split = try XCTUnwrap(latest)
        XCTAssertFalse(split.needsHTML)
    }

    @MainActor
    func testCellAlignmentAppliesToOneCellNotTheWholeColumn() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |\n| 3 | 4 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        _ = try XCTUnwrap(findCell(in: grid, containing: "1")).becomeFirstResponder()
        XCTAssertTrue(bridge.apply(.setCellAlignment(.right)))

        let table = try XCTUnwrap(latest)
        XCTAssertEqual(table.rows[0].cells[0].horizontalAlignment, .right)
        XCTAssertNil(table.rows[1].cells[0].horizontalAlignment, "The cell below must be untouched")
        XCTAssertEqual(table.alignments[0], .none, "The column itself must be untouched")
    }

    @MainActor
    func testColumnAlignmentClearsPerCellOverridesInThatColumn() throws {
        let grid = try gridForTable("| A |\n| --- |\n| 1 |\n| 2 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        _ = try XCTUnwrap(findCell(in: grid, containing: "1")).becomeFirstResponder()
        XCTAssertTrue(bridge.apply(.setCellAlignment(.right)))
        XCTAssertTrue(bridge.apply(.setAlignment(.center)))

        let table = try XCTUnwrap(latest)
        XCTAssertEqual(table.alignments[0], .center)
        XCTAssertNil(
            table.rows[0].cells[0].horizontalAlignment,
            "Aligning the whole column plainly means the overrides in it are gone"
        )
        XCTAssertFalse(table.needsHTML, "With the overrides cleared it is plain Markdown again")
    }

    @MainActor
    func testVerticalAlignmentReachesTheModel() throws {
        let grid = try gridForTable("| A |\n| --- |\n| 1 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        _ = try XCTUnwrap(findCell(in: grid, containing: "1")).becomeFirstResponder()
        XCTAssertTrue(bridge.apply(.setCellVerticalAlignment(.bottom)))

        XCTAssertEqual(try XCTUnwrap(latest).rows[0].cells[0].verticalAlignment, .bottom)
        XCTAssertEqual(try XCTUnwrap(bridge.context).cellVerticalAlignment, .bottom)
    }

    @MainActor
    func testSourceModeReportsThatItCannotDoCellFeatures() throws {
        // Source mode derives its context from Markdown text, which has no way
        // to express a merge — so the panel must not offer one.
        let context = try XCTUnwrap(
            MarkdownFormatter.tableContext(in: "| A | B |\n| --- | --- |\n| 1 | 2 |", at: 2)
        ).editingContext

        XCTAssertFalse(context.supportsCellFeatures)
        XCTAssertFalse(context.canMergeRight)
        XCTAssertFalse(context.canMergeDown)
    }

    @MainActor
    func testAMergedGridLaysOutWithoutOverlappingCells() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        var table = grid.table
        table.header.cells[0].columnSpan = 2
        table.normalize()

        let rebuilt = DocumentTableView(table: table, blockID: UUID(), theme: .standard)
        rebuilt.frame = NSRect(x: 0, y: 0, width: 620, height: rebuilt.measuredHeight(for: 620))
        rebuilt.layoutSubtreeIfNeeded()

        let visible = rebuilt.subviews.compactMap { $0 as? TableCellTextView }.filter { !$0.isHidden }
        XCTAssertEqual(visible.count, 3, "A 2×2 grid with one merged header pair shows three cells")

        for (index, cell) in visible.enumerated() {
            for other in visible[(index + 1)...] where cell !== other {
                XCTAssertFalse(
                    cell.frame.intersects(other.frame),
                    "Cells must not overlap: \(cell.frame) and \(other.frame)"
                )
            }
        }
    }

    // MARK: - Following a citation to its place in the document

    /// The assistant quotes the *source*, so a citation arrives carrying
    /// Markdown. Neither the canvas nor the preview contains that syntax — a
    /// task marker is a checkbox, a link is its label — so a quote that keeps
    /// it finds nothing and the citation appears dead when clicked.
    func testQuoteStrippingRemovesSyntaxThatIsNeverOnScreen() {
        let cases: [(String, String)] = [
            ("- [x] Mermaid diagrams rendered locally", "Mermaid diagrams rendered locally"),
            ("- [ ] Windows edition", "Windows edition"),
            ("## Why Markowski", "Why Markowski"),
            ("- Regular bullet item", "Regular bullet item"),
            ("1. First numbered step", "First numbered step"),
            ("> A quoted aside", "A quoted aside"),
            ("Some **bold** prose", "Some bold prose"),
            ("A [link](https://example.com) inside", "A link inside"),
            ("An ![image](shot.png) here", "An image here")
        ]
        for (markdown, expected) in cases {
            XCTAssertEqual(
                DocumentIndex.plainText(fromMarkdown: markdown), expected,
                "Stripping \(markdown.debugDescription)"
            )
        }
    }

    func testQuoteCandidatesOfferTheStrippedForm() {
        let candidates = DocumentIndex.quoteCandidates(for: "- [x] Mermaid diagrams rendered locally")
        XCTAssertTrue(
            candidates.contains("Mermaid diagrams rendered locally"),
            "The on-screen form has to be among the things searched for. Got: \(candidates)"
        )
    }

    /// End to end through the real canvas: a citation quoting a task item has
    /// to actually land on that line.
    @MainActor
    func testCitationQuotingATaskItemFindsItInTheCanvas() throws {
        let (_, textView, _) = makeCanvas("""
        # Launch

        ## Everything stays in flow

        - [x] Mermaid diagrams rendered locally
        - [ ] Windows edition

        Some **bold** prose with a [link](https://example.com) inside it.
        """)

        let navigator = DocumentNavigator()
        navigator.attachCanvas(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        navigator.navigateToLocation(
            DocumentLocation(heading: nil, quote: "- [x] Mermaid diagrams rendered locally",
                             startLine: nil, endLine: nil, blockId: nil),
            text: textView.string,
            viewMode: .editor,
            reduceMotion: true
        )

        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        XCTAssertTrue(
            selected.contains("Mermaid diagrams rendered locally"),
            "The caret should be on the cited line; it selected \(selected.debugDescription)"
        )
    }

    /// A quote whose sentence contains inline formatting has to match too —
    /// the canvas holds the words without the asterisks or the link target.
    @MainActor
    func testCitationWithInlineFormattingFindsItsSentence() throws {
        let (_, textView, _) = makeCanvas("""
        # Launch

        Some **bold** prose with a [link](https://example.com) inside it.
        """)

        let navigator = DocumentNavigator()
        navigator.attachCanvas(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        navigator.navigateToLocation(
            DocumentLocation(heading: nil,
                             quote: "Some **bold** prose with a [link](https://example.com) inside it.",
                             startLine: nil, endLine: nil, blockId: nil),
            text: textView.string,
            viewMode: .editor,
            reduceMotion: true
        )

        let selected = (textView.string as NSString).substring(with: textView.selectedRange())
        XCTAssertTrue(
            selected.contains("bold prose"),
            "Got: \(selected.debugDescription)"
        )
    }

    @MainActor
    func testCitationThatMatchesNothingLeavesTheCaretAlone() throws {
        let (_, textView, _) = makeCanvas("# Launch\n\nOnly this paragraph exists.")

        let navigator = DocumentNavigator()
        navigator.attachCanvas(textView)
        textView.setSelectedRange(NSRange(location: 0, length: 0))

        navigator.navigateToLocation(
            DocumentLocation(heading: nil, quote: "a passage that is nowhere in this document",
                             startLine: nil, endLine: nil, blockId: nil),
            text: textView.string,
            viewMode: .editor,
            reduceMotion: true
        )

        XCTAssertEqual(
            textView.selectedRange().length, 0,
            "Nothing matched, so nothing should have been selected"
        )
    }

    // MARK: - Images

    func testStandaloneImageIsRecognisedAndRoundTrips() {
        // Markdown writes an image as "!" plus a link, so this is the shape the
        // canvas has to spot.
        let document = MarkdownDocumentParser.parse("![A diagram](shots/diagram.png)")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }

        let image = RichTextRenderer.standaloneImage(in: text)
        XCTAssertEqual(image?.source, "shots/diagram.png")
        XCTAssertEqual(image?.alt, "A diagram")

        assertProjectionIsIdentity("![A diagram](shots/diagram.png)")
    }

    func testTextThatMerelyEndsInAnExclamationIsNotAnImage() {
        let document = MarkdownDocumentParser.parse("Wow! [a link](https://example.com)")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertNil(
            RichTextRenderer.standaloneImage(in: text),
            "Only a paragraph that is exactly !+link is an image"
        )
    }

    @MainActor
    func testImageShowsAsAnAttachmentRatherThanItsSyntax() throws {
        let (_, textView, binding) = makeCanvas("![Shot](picture.png)")
        let storage = try XCTUnwrap(textView.textStorage)

        XCTAssertFalse(textView.string.contains("!["), "The canvas must never show Markdown syntax")
        var found: DocumentImageAttachment?
        storage.enumerateAttribute(.attachment, in: storage.fullRange, options: []) { value, _, stop in
            if let attachment = value as? DocumentImageAttachment {
                found = attachment
                stop.pointee = true
            }
        }
        let attachment = try XCTUnwrap(found, "A standalone image should become an attachment")
        XCTAssertEqual(attachment.source, "picture.png")

        // And it still saves as the same Markdown.
        XCTAssertEqual(binding.wrappedValue.trimmingCharacters(in: .whitespacesAndNewlines), "![Shot](picture.png)")
    }

    func testImagePathResolutionIsRelativeToTheDocument() throws {
        let base = URL(fileURLWithPath: "/Users/someone/Notes")
        XCTAssertEqual(
            DocumentImageAttachment.resolve(source: "img/a.png", baseURL: base)?.path,
            "/Users/someone/Notes/img/a.png"
        )
        XCTAssertEqual(
            DocumentImageAttachment.resolve(source: "/tmp/b.png", baseURL: base)?.path,
            "/tmp/b.png"
        )
        XCTAssertNil(
            DocumentImageAttachment.resolve(source: "https://example.com/c.png", baseURL: base),
            "A remote image is the web view's job, not a local file read"
        )
    }

    /// The preview page is confined to the app bundle, so the host serves the
    /// document's own images. That handler must find real ones and refuse
    /// anything that isn't an image.
    @MainActor
    func testLocalResourceHandlerResolvesDocumentImages() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("markowski-images-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let png = directory.appendingPathComponent("shot.png")
        let image = NSImage(size: NSSize(width: 4, height: 4))
        image.lockFocus()
        NSColor.red.drawSwatch(in: NSRect(x: 0, y: 0, width: 4, height: 4))
        image.unlockFocus()
        try XCTUnwrap(
            NSBitmapImageRep(data: try XCTUnwrap(image.tiffRepresentation))?
                .representation(using: .png, properties: [:])
        ).write(to: png)

        let secret = directory.appendingPathComponent("secrets.txt")
        try "not an image".write(to: secret, atomically: true, encoding: .utf8)

        let handler = LocalResourceSchemeHandler()
        handler.documentDirectory = directory

        func resolve(_ path: String) -> URL? {
            handler.resolve(URL(string: "mvlocal://doc/?p=\(path.addingPercentEncoding(withAllowedCharacters: .alphanumerics)!)")!)
        }

        XCTAssertEqual(resolve("shot.png")?.lastPathComponent, "shot.png")
        XCTAssertNil(resolve("secrets.txt"), "Only images are served")
        XCTAssertNil(resolve("missing.png"), "A file that isn't there resolves to nothing")
    }

    // MARK: - The floating selection toolbar

    @MainActor
    func testBlockStyleReadbackNamesWhatTheSelectionIs() throws {
        let (_, textView, _) = makeCanvas("# Title\n\nBody text.\n\n- an item\n\n> quoted")

        func style(at needle: String) throws -> BlockStyleChoice? {
            let range = (textView.string as NSString).range(of: needle)
            textView.setSelectedRange(NSRange(location: range.location, length: 0))
            return textView.currentBlockStyle
        }

        XCTAssertEqual(try style(at: "Title"), .heading1)
        XCTAssertEqual(try style(at: "Body text."), .body)
        XCTAssertEqual(try style(at: "an item"), .bulletList)
        XCTAssertEqual(try style(at: "quoted"), .quote)
    }

    @MainActor
    func testBlockStyleReadbackIsUndefinedAcrossMixedBlocks() {
        let (_, textView, _) = makeCanvas("# Title\n\nBody text.")
        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))

        XCTAssertNil(
            textView.currentBlockStyle,
            "A selection spanning a heading and a paragraph is not any one style"
        )
    }

    @MainActor
    func testApplyingABlockStyleConvertsAndIsIdempotent() {
        let (_, textView, binding) = makeCanvas("Body text.")
        textView.setSelectedRange(NSRange(location: 2, length: 0))

        textView.applyBlockStyle(.heading2)
        XCTAssertTrue(binding.wrappedValue.contains("## Body text."), "Got: \(binding.wrappedValue)")

        // Choosing the same entry again is a no-op, not a toggle back off.
        let afterFirst = binding.wrappedValue
        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.applyBlockStyle(.heading2)
        XCTAssertEqual(binding.wrappedValue, afterFirst, "A menu choice is not a toggle")
    }

    @MainActor
    func testBlockStyleBodyUnwrapsWhateverItCurrentlyIs() {
        for (markdown, needle) in [
            ("- an item", "an item"),
            ("> quoted", "quoted"),
            ("1. first", "first")
        ] {
            let (_, textView, binding) = makeCanvas(markdown)
            let range = (textView.string as NSString).range(of: needle)
            textView.setSelectedRange(NSRange(location: range.location, length: 0))

            textView.applyBlockStyle(.body)

            XCTAssertEqual(
                textView.currentBlockStyle, .body,
                "\(markdown) should have become body text; got \(binding.wrappedValue)"
            )
        }
    }

    /// The bar exists to act on a live selection, so nothing in it may take
    /// first responder — the selection would be gone before the command ran.
    @MainActor
    func testSelectionToolbarNeverTakesFocus() {
        let toolbar = SelectionToolbar()
        toolbar.layoutSubtreeIfNeeded()

        XCTAssertFalse(toolbar.acceptsFirstResponder)

        func assertNoneAcceptFocus(_ view: NSView) {
            for subview in view.subviews {
                XCTAssertFalse(
                    subview.acceptsFirstResponder,
                    "\(String(describing: Swift.type(of: subview))) in the selection bar would steal the selection"
                )
                assertNoneAcceptFocus(subview)
            }
        }
        assertNoneAcceptFocus(toolbar)
    }

    @MainActor
    func testSelectionToolbarStaysHiddenWithoutASelection() {
        let (_, textView, _) = makeCanvas("Some text here.")
        textView.setSelectedRange(NSRange(location: 3, length: 0))
        textView.updateSelectionToolbar()

        let bars = textView.subviews.compactMap { $0 as? SelectionToolbar }
        XCTAssertTrue(
            bars.allSatisfy(\.isHidden),
            "With only a caret there is nothing for the bar to act on"
        )
    }

    // MARK: - Native block commands

    @MainActor
    func testToggleListConvertsParagraphsAndBack() {
        let (_, textView, binding) = makeCanvas("Intro.\n\nFirst point.\n\nOutro.")

        let range = (textView.string as NSString).range(of: "First point.")
        textView.setSelectedRange(NSRange(location: range.location + 2, length: 0))
        textView.toggleList(ordered: false, checkbox: false)

        XCTAssertTrue(binding.wrappedValue.contains("- First point."), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("Intro."), "Other blocks must be untouched")

        // Toggling again unwraps.
        let itemRange = (textView.string as NSString).range(of: "First point.")
        textView.setSelectedRange(NSRange(location: itemRange.location, length: 0))
        textView.toggleList(ordered: false, checkbox: false)
        XCTAssertFalse(binding.wrappedValue.contains("- First point."), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("First point."))
    }

    @MainActor
    func testToggleListJoinsAMultiParagraphSelectionIntoOneList() {
        let (_, textView, binding) = makeCanvas("One.\n\nTwo.\n\nThree.")

        textView.setSelectedRange(NSRange(location: 0, length: (textView.string as NSString).length))
        textView.toggleList(ordered: true, checkbox: false)

        XCTAssertTrue(binding.wrappedValue.contains("1. One."), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("2. Two."))
        XCTAssertTrue(binding.wrappedValue.contains("3. Three."))
    }

    @MainActor
    func testChecklistCommandAddsAndBulletCommandRemovesCheckboxes() {
        let (_, textView, binding) = makeCanvas("- alpha\n- beta")

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.toggleList(ordered: false, checkbox: true)
        XCTAssertTrue(binding.wrappedValue.contains("- [ ] alpha"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("- [ ] beta"))

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.toggleList(ordered: false, checkbox: false)
        XCTAssertTrue(binding.wrappedValue.contains("- alpha"), "Got: \(binding.wrappedValue)")
        XCTAssertFalse(binding.wrappedValue.contains("[ ]"))
    }

    @MainActor
    func testToggleQuoteWrapsAndUnwraps() {
        let (_, textView, binding) = makeCanvas("A thought.")

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.toggleQuote()
        XCTAssertTrue(binding.wrappedValue.contains("> A thought."), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange(NSRange(location: 2, length: 0))
        textView.toggleQuote()
        XCTAssertFalse(binding.wrappedValue.contains(">"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("A thought."))
    }

    @MainActor
    func testToggleCodeBlockWrapsProseAndUnwrapsCode() {
        let (_, textView, binding) = makeCanvas("let x = 1")

        textView.setSelectedRange(NSRange(location: 0, length: 0))
        textView.toggleCodeBlock()
        XCTAssertTrue(binding.wrappedValue.contains("```\nlet x = 1\n```"), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange(NSRange(location: 1, length: 0))
        textView.toggleCodeBlock()
        XCTAssertFalse(binding.wrappedValue.contains("```"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("let x = 1"))
    }

    @MainActor
    func testInsertDividerAndTableLandBelowTheCurrentBlock() {
        let (_, textView, binding) = makeCanvas("Above.\n\nBelow.")

        let above = (textView.string as NSString).range(of: "Above.")
        textView.setSelectedRange(NSRange(location: above.location + 2, length: 0))
        textView.insertDivider()

        let markdown = binding.wrappedValue
        let dividerIndex = markdown.range(of: "---")
        let belowIndex = markdown.range(of: "Below.")
        XCTAssertNotNil(dividerIndex, "Got: \(markdown)")
        if let dividerIndex, let belowIndex {
            XCTAssertLessThan(dividerIndex.lowerBound, belowIndex.lowerBound, "The rule goes after the caret's block")
        }

        textView.insertTable(rows: 2, columns: 3)
        XCTAssertTrue(binding.wrappedValue.contains("| Column 1 | Column 2 | Column 3 |"), "Got: \(binding.wrappedValue)")
    }

    @MainActor
    func testBlockDirectionWrapsAndUnwrapsTheCaretBlock() {
        let (_, textView, binding) = makeCanvas("First.\n\nSecond.")

        let second = (textView.string as NSString).range(of: "Second.")
        textView.setSelectedRange(NSRange(location: second.location + 1, length: 0))
        textView.setBlockDirection(rightToLeft: true)

        XCTAssertTrue(binding.wrappedValue.contains("<div dir=\"rtl\" markdown=\"1\">"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("Second."))
        XCTAssertFalse(binding.wrappedValue.contains("<div dir=\"rtl\" markdown=\"1\">\nFirst."), "The wrong block must not be wrapped")

        // Same direction again unwraps.
        let wrapped = (textView.string as NSString).range(of: "Second.")
        textView.setSelectedRange(NSRange(location: wrapped.location, length: 0))
        textView.setBlockDirection(rightToLeft: true)
        XCTAssertFalse(binding.wrappedValue.contains("<div"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("Second."))
    }

    @MainActor
    func testRewriteSelectionTransformsOnlyTheSelectedText() {
        let (_, textView, binding) = makeCanvas("Price 123 and 456 here.")

        let range = (textView.string as NSString).range(of: "123")
        textView.setSelectedRange(range)
        textView.rewriteSelection(PersianTextTools.toPersianDigits)

        XCTAssertTrue(binding.wrappedValue.contains("۱۲۳"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("456"), "Unselected digits stay Latin")
    }

    @MainActor
    func testApplyLinkAndRemoveIt() {
        let (_, textView, binding) = makeCanvas("Visit the site today.")

        let range = (textView.string as NSString).range(of: "the site")
        textView.setSelectedRange(range)
        textView.applyLink("https://example.com")
        XCTAssertTrue(binding.wrappedValue.contains("[the site](https://example.com)"), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange((textView.string as NSString).range(of: "the site"))
        XCTAssertTrue(textView.selectionIsEntirelyLinked)
        textView.applyLink(nil)
        XCTAssertFalse(binding.wrappedValue.contains("example.com"), "Got: \(binding.wrappedValue)")
    }

    @MainActor
    func testToggleCheckboxFlipsTheGlyphAndTheSavedState() {
        let (_, textView, binding) = makeCanvas("- [ ] buy milk")

        let box = (textView.string as NSString).range(of: "☐")
        XCTAssertNotEqual(box.location, NSNotFound)
        textView.toggleCheckbox(at: box.location)

        XCTAssertTrue(textView.string.contains("☑"))
        XCTAssertTrue(binding.wrappedValue.contains("- [x] buy milk"), "Got: \(binding.wrappedValue)")

        textView.toggleCheckbox(at: (textView.string as NSString).range(of: "☑").location)
        XCTAssertTrue(binding.wrappedValue.contains("- [ ] buy milk"), "Got: \(binding.wrappedValue)")
    }

    @MainActor
    func testTabIndentsAListItemAndShiftTabOutdentsIt() {
        let (_, textView, binding) = makeCanvas("- parent\n- child")

        let child = (textView.string as NSString).range(of: "child")
        textView.setSelectedRange(NSRange(location: child.location, length: 0))
        textView.insertTab(nil)

        XCTAssertTrue(binding.wrappedValue.contains("  - child"), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).range(of: "child").location, length: 0))
        textView.insertBacktab(nil)
        XCTAssertFalse(binding.wrappedValue.contains("  - child"), "Got: \(binding.wrappedValue)")
        XCTAssertFalse(textView.string.contains("\t\t"), "Tab must never become a literal character in a list")
    }

    // MARK: - Typing autoformat

    @MainActor
    private func type(_ text: String, into textView: CanvasTextView) {
        for character in text {
            textView.insertText(String(character), replacementRange: textView.selectedRange())
        }
    }

    @MainActor
    func testTypingAMarkdownPrefixConvertsTheParagraph() {
        let (_, textView, binding) = makeCanvas("Existing.")

        // A fresh paragraph after the existing one.
        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertNewline(nil)
        type("- Milk", into: textView)

        XCTAssertTrue(binding.wrappedValue.contains("- Milk"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(textView.string.contains("•"), "The canvas shows a bullet, not the dash")

        textView.insertNewline(nil)
        type("Bread", into: textView)
        XCTAssertTrue(binding.wrappedValue.contains("- Bread"), "Return continues the list; got: \(binding.wrappedValue)")
    }

    @MainActor
    func testTypingHashSpaceMakesAHeading() {
        let (_, textView, binding) = makeCanvas("Existing.")

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertNewline(nil)
        type("## Chapter", into: textView)

        XCTAssertTrue(binding.wrappedValue.contains("## Chapter"), "Got: \(binding.wrappedValue)")
        XCTAssertFalse(textView.string.contains("#"), "The hashes are consumed, not shown")
    }

    @MainActor
    func testTypingNumberedPrefixStartsAnOrderedList() {
        let (_, textView, binding) = makeCanvas("Existing.")

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertNewline(nil)
        type("1. First", into: textView)

        XCTAssertTrue(binding.wrappedValue.contains("1. First"), "Got: \(binding.wrappedValue)")
    }

    @MainActor
    func testTypingFenceThenReturnMakesACodeBlock() {
        let (_, textView, binding) = makeCanvas("Existing.")

        textView.setSelectedRange(NSRange(location: (textView.string as NSString).length, length: 0))
        textView.insertNewline(nil)
        type("```swift", into: textView)
        textView.insertNewline(nil)
        type("let x = 1", into: textView)

        XCTAssertTrue(binding.wrappedValue.contains("```swift"), "Got: \(binding.wrappedValue)")
        XCTAssertTrue(binding.wrappedValue.contains("let x = 1"))
        XCTAssertFalse(textView.string.contains("`"), "The fence itself never appears in the canvas")
    }

    // MARK: - Highlight

    func testHighlightRoundTripsThroughMarkdown() {
        assertProjectionIsIdentity("Text with ==marked== words.")

        let document = MarkdownDocumentParser.parse("A ==big deal== here.")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertTrue(text.runs.contains { $0.style.contains(.highlight) && $0.text == "big deal" })

        let serialized = MarkdownDocumentSerializer.serialize(document)
        XCTAssertTrue(serialized.contains("==big deal=="), "Got: \(serialized)")
    }

    func testLiteralDoubleEqualsSurvivesTheRoundTrip() {
        let document = RichDocument(blocks: [
            RichBlock(content: .paragraph(InlineText(plain: "if a == b then")))
        ])
        let serialized = MarkdownDocumentSerializer.serialize(document)
        let reparsed = MarkdownDocumentParser.parse(serialized)
        XCTAssertTrue(document.hasSameContent(as: reparsed), "Got: \(serialized)")
    }

    @MainActor
    func testHighlightCommandTogglesInTheCanvas() {
        let (_, textView, binding) = makeCanvas("shine a light")

        let range = (textView.string as NSString).range(of: "light")
        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.highlight)
        XCTAssertTrue(binding.wrappedValue.contains("==light=="), "Got: \(binding.wrappedValue)")

        textView.setSelectedRange(range)
        textView.toggleInlineStyle(.highlight)
        XCTAssertFalse(binding.wrappedValue.contains("=="), "Got: \(binding.wrappedValue)")
    }

    @MainActor
    func testGeneratedChromeCannotBeEdited() throws {
        let (_, textView, _) = makeCanvas("- an item")
        let coordinator = try XCTUnwrap(textView.delegate as? RichTextCanvas.Coordinator)

        // The bullet and its tab are chrome, not content.
        let bulletRange = (textView.string as NSString).range(of: "•")
        XCTAssertFalse(
            coordinator.textView(textView, shouldChangeTextIn: bulletRange, replacementString: "x"),
            "Deleting the bullet would leave the list structure meaningless"
        )

        // The item's own text is perfectly editable.
        let textRange = (textView.string as NSString).range(of: "an item")
        XCTAssertTrue(coordinator.textView(textView, shouldChangeTextIn: textRange, replacementString: "x"))
    }

    @MainActor
    func testExternalChangeIsProjectedButOwnEditIsNot() {
        let (hosting, textView, binding) = makeCanvas("Original text.")

        // A change from outside the canvas — a reload, or an applied AI edit.
        binding.wrappedValue = "# Replaced\n\nNew body."
        hosting.rootView = RichTextCanvas(markdown: binding)
        hosting.layoutSubtreeIfNeeded()

        XCTAssertTrue(textView.string.contains("Replaced"))
        XCTAssertTrue(textView.string.contains("New body."))
        XCTAssertFalse(textView.string.contains("Original"))
    }

    @MainActor
    func testCanvasLaysOutWithRealHeight() {
        let (_, textView, _) = makeCanvas("""
        # Title

        A paragraph long enough to need more than a single line when it is laid         out inside a nine-hundred point wide canvas like this one.

        - one
        - two
        """)

        XCTAssertGreaterThan(textView.frame.height, 100, "The canvas laid out to nothing")
        XCTAssertGreaterThan(textView.frame.width, 0)
    }

    // MARK: - The formatting panel and the selected table

    @MainActor
    private func gridForTable(_ markdown: String) throws -> DocumentTableView {
        let document = MarkdownDocumentParser.parse(markdown)
        let attachment = try XCTUnwrap(tableAttachment(in: RichTextRenderer.attributedString(for: document)))
        let grid = DocumentTableView(table: attachment.table, blockID: attachment.blockID, theme: .standard)
        grid.frame = NSRect(x: 0, y: 0, width: 620, height: 200)
        grid.layoutSubtreeIfNeeded()
        return grid
    }

    /// The panel's table controls went dead when tables became attachments:
    /// nothing reading Markdown source can see a caret inside one.
    @MainActor
    func testFocusingACellPublishesATableContext() throws {
        let grid = try gridForTable("| A | B | C |\n| --- | :---: | --- |\n| 1 | 2 | 3 |")
        let bridge = TableSelectionBridge()

        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }

        XCTAssertNil(bridge.context, "No table is selected until a cell takes focus")

        let cell = try XCTUnwrap(findCell(in: grid, containing: "2"))
        _ = cell.becomeFirstResponder()

        let context = try XCTUnwrap(bridge.context)
        XCTAssertEqual(context.caretRow, 1, "Row 0 is the header, so '2' is in row 1")
        XCTAssertEqual(context.caretColumn, 1)
        XCTAssertEqual(context.rowCount, 2)
        XCTAssertEqual(context.columnCount, 3)
        XCTAssertEqual(context.currentAlignment, .center)
    }

    @MainActor
    func testPanelCommandsReachTheLiveGrid() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }

        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        _ = try XCTUnwrap(findCell(in: grid, containing: "2")).becomeFirstResponder()

        XCTAssertTrue(bridge.apply(.addRow))
        XCTAssertEqual(try XCTUnwrap(latest).rows.count, 2)

        XCTAssertTrue(bridge.apply(.addColumn))
        XCTAssertEqual(try XCTUnwrap(latest).columnCount, 3)

        XCTAssertTrue(bridge.apply(.setAlignment(.right)))
        let aligned = try XCTUnwrap(latest)
        XCTAssertEqual(aligned.alignments[try XCTUnwrap(bridge.context).caretColumn], .right)

        XCTAssertTrue(bridge.apply(.deleteColumn))
        XCTAssertEqual(try XCTUnwrap(latest).columnCount, 2)
    }

    @MainActor
    func testBridgeRefusesWhatTheTableCannotDo() throws {
        let grid = try gridForTable("| A |\n| --- |\n| 1 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }

        // A header cell: deleting its row would destroy the table.
        _ = try XCTUnwrap(findCell(in: grid, containing: "A")).becomeFirstResponder()
        XCTAssertFalse(try XCTUnwrap(bridge.context).canDeleteRow)
        XCTAssertFalse(bridge.apply(.deleteRow))

        // The only column: deleting it would leave nothing.
        XCTAssertFalse(try XCTUnwrap(bridge.context).canDeleteColumn)
        XCTAssertFalse(bridge.apply(.deleteColumn))

        // With no table focused at all, every command is refused rather than
        // silently applied somewhere else.
        bridge.clear()
        XCTAssertFalse(bridge.apply(.addRow))
    }

    // MARK: - The grid's own controls

    /// Every control has to be inside the height the attachment reserves.
    /// Both "+" buttons used to be drawn past the bottom and trailing edges of
    /// a view sized to its rows alone, so they were clipped away and could
    /// never be clicked — the table had no working affordances at all.
    @MainActor
    func testGutterControlsFitInsideTheMeasuredHeight() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let height = grid.measuredHeight(for: 620)
        grid.frame = NSRect(x: 0, y: 0, width: 620, height: height)
        grid.layoutSubtreeIfNeeded()

        let controls = grid.subviews.compactMap { $0 as? TableGutterButton }
        XCTAssertFalse(controls.isEmpty, "The grid should offer row, column, and add controls")

        for control in controls {
            XCTAssertTrue(
                grid.bounds.contains(control.frame),
                "\(control.toolTip ?? "a control") is outside the grid at \(control.frame), bounds \(grid.bounds)"
            )
        }
    }

    @MainActor
    func testMeasuredHeightLeavesRoomForTheControlGutters() throws {
        let grid = try gridForTable("| A |\n| --- |\n| 1 |")
        let rowsOnly = grid.subviews.compactMap { $0 as? TableCellTextView }
            .map(\.frame.height).reduce(0, +)

        XCTAssertGreaterThan(
            grid.measuredHeight(for: 620), rowsOnly,
            "The measurement has to include the gutters, or the controls get clipped"
        )
    }

    @MainActor
    func testClickingACellRegionFocusesThatCell() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        grid.frame = NSRect(x: 0, y: 0, width: 620, height: grid.measuredHeight(for: 620))
        grid.layoutSubtreeIfNeeded()

        // The padding around a cell's text belongs to that cell.
        let cell = try XCTUnwrap(findCell(in: grid, containing: "2"))
        let justOutsideText = NSPoint(x: cell.frame.midX, y: cell.frame.minY - 3)

        let window = NSWindow(
            contentRect: grid.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(grid)
        window.makeKeyAndOrderFront(nil)

        let event = try XCTUnwrap(NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: grid.convert(justOutsideText, to: nil),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ))
        grid.mouseDown(with: event)

        XCTAssertTrue(window.firstResponder === cell, "Clicking a cell's padding should put the caret in it")
    }

    @MainActor
    func testMovingARowReordersTheModel() throws {
        let grid = try gridForTable("| A |\n| --- |\n| one |\n| two |")
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        // Row 2 in all-rows space is the body row "two".
        grid.moveRow(at: 2, by: -1)

        let table = try XCTUnwrap(latest)
        XCTAssertEqual(table.rows.map(\.cells[0].content.plainText), ["two", "one"])
    }

    @MainActor
    func testMovingAColumnCarriesItsCellsAndAlignment() throws {
        let grid = try gridForTable("| A | B |\n| :--- | ---: |\n| 1 | 2 |")
        var latest: TableBlock?
        grid.onChange = { _, table in latest = table }

        grid.moveColumn(at: 0, by: 1)

        let table = try XCTUnwrap(latest)
        XCTAssertEqual(table.header.cells.map(\.content.plainText), ["B", "A"])
        XCTAssertEqual(table.rows[0].cells.map(\.content.plainText), ["2", "1"])
        XCTAssertEqual(table.alignments, [.right, .left], "Alignment travels with its column")
    }

    @MainActor
    func testMoveRefusesToPushARowPastTheEnds() throws {
        let grid = try gridForTable("| A |\n| --- |\n| one |\n| two |")
        var changes = 0
        grid.onChange = { _, _ in changes += 1 }

        grid.moveRow(at: 1, by: -1)   // already the first body row
        grid.moveRow(at: 2, by: 1)    // already the last
        grid.moveRow(at: 0, by: 1)    // the header is not movable

        XCTAssertEqual(changes, 0, "None of those are legal moves, so nothing should change")
    }

    @MainActor
    func testTypingATallCellGrowsTheMeasuredHeight() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        grid.frame = NSRect(x: 0, y: 0, width: 320, height: grid.measuredHeight(for: 320))
        grid.layoutSubtreeIfNeeded()
        let before = grid.measuredHeight(for: 320)

        let cell = try XCTUnwrap(findCell(in: grid, containing: "2"))
        cell.insertText(
            String(repeating: "long wrapping cell content ", count: 8),
            replacementRange: NSRange(location: 0, length: 0)
        )
        grid.layoutSubtreeIfNeeded()

        XCTAssertGreaterThan(
            grid.measuredHeight(for: 320), before,
            "A cell that wraps onto more lines has to make its row taller, or the text is clipped"
        )
    }

    @MainActor
    func testArrowKeysMoveBetweenRows() throws {
        let grid = try gridForTable("| A |\n| --- |\n| one |\n| two |")
        grid.frame = NSRect(x: 0, y: 0, width: 620, height: grid.measuredHeight(for: 620))
        grid.layoutSubtreeIfNeeded()

        let window = NSWindow(
            contentRect: grid.frame,
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView?.addSubview(grid)
        window.makeKeyAndOrderFront(nil)

        let first = try XCTUnwrap(findCell(in: grid, containing: "one"))
        window.makeFirstResponder(first)
        first.moveDown(nil)

        let second = try XCTUnwrap(findCell(in: grid, containing: "two"))
        XCTAssertTrue(window.firstResponder === second, "Down from the last line of a cell goes to the row below")

        second.moveUp(nil)
        XCTAssertTrue(window.firstResponder === first, "Up from the first line goes back")
    }

    @MainActor
    func testCellsRenderCodeAndHighlightStyles() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| `code` | ==mark== |")

        let code = try XCTUnwrap(findCell(in: grid, containing: "code"))
        let codeFont = try XCTUnwrap(
            code.textStorage?.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        )
        XCTAssertTrue(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))

        let mark = try XCTUnwrap(findCell(in: grid, containing: "mark"))
        XCTAssertNotNil(
            mark.textStorage?.attribute(.backgroundColor, at: 0, effectiveRange: nil),
            "A highlighted cell should look highlighted"
        )
    }

    @MainActor
    func testContextTracksTheCaretAfterAStructuralChange() throws {
        let grid = try gridForTable("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let bridge = TableSelectionBridge()
        grid.onSelectionChange = { grid, context in
            if let context { bridge.focus(grid, context: context) } else { bridge.release(grid) }
        }

        _ = try XCTUnwrap(findCell(in: grid, containing: "2")).becomeFirstResponder()
        XCTAssertEqual(try XCTUnwrap(bridge.context).rowCount, 2)

        bridge.apply(.addRow)
        // The panel must show the table as it now is, not as it was.
        let context = try XCTUnwrap(bridge.context)
        XCTAssertEqual(context.rowCount, 3)
        XCTAssertEqual(context.caretColumn, 1, "The caret stays in the column it was in")
    }

    @MainActor
    func testReleaseOnlyClearsTheGridThatHadFocus() throws {
        let first = try gridForTable("| A |\n| --- |\n| 1 |")
        let second = try gridForTable("| B |\n| --- |\n| 2 |")
        let bridge = TableSelectionBridge()

        bridge.focus(first, context: first.currentEditingContext(row: 1, column: 0))
        bridge.focus(second, context: second.currentEditingContext(row: 1, column: 0))

        // Moving between tables fires the old grid's release after the new
        // grid's focus; that must not blank the panel.
        bridge.release(first)
        XCTAssertNotNil(bridge.context, "The newly focused table is still selected")

        bridge.release(second)
        XCTAssertNil(bridge.context)
    }

    @MainActor
    func testSourceModeTableContextStillWorks() throws {
        let markdown = "| A | B |\n| :--- | ---: |\n| 1 | 2 |"
        let caret = (markdown as NSString).range(of: "2").location
        let formatterContext = try XCTUnwrap(MarkdownFormatter.tableContext(in: markdown, at: caret))

        // Source mode keeps its own finder and converts into the shared shape.
        let context = formatterContext.editingContext
        XCTAssertEqual(context.columnCount, 2)
        XCTAssertEqual(context.alignments, [.left, .right])
        XCTAssertEqual(context.caretRow, 1)
        XCTAssertTrue(context.canDeleteRow)
    }
}
