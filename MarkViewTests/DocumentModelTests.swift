import XCTest
@testable import MarkView

/// The document model is the source of truth and Markdown is only its storage
/// format — which is only safe if the two directions agree. Everything here
/// exists to hold that line.
final class DocumentModelTests: XCTestCase {

    // MARK: - Helpers

    /// Parse → serialize → parse must reach a fixed point. The first
    /// serialization may normalise the author's formatting (`__x__` → `**x**`),
    /// but from then on the content must never drift again.
    private func assertRoundTrips(
        _ markdown: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let first = MarkdownDocumentParser.parse(markdown)
        let written = MarkdownDocumentSerializer.serialize(first)
        let second = MarkdownDocumentParser.parse(written)

        XCTAssertTrue(
            first.hasSameContent(as: second),
            """
            Round trip changed the document.
            source:     \(markdown.debugDescription)
            written:    \(written.debugDescription)
            first:      \(first.blocks.map(\.content))
            second:     \(second.blocks.map(\.content))
            """,
            file: file, line: line
        )

        // And serialising the reparsed document is byte-identical: stable.
        XCTAssertEqual(
            MarkdownDocumentSerializer.serialize(second),
            written,
            "Serialization is not idempotent",
            file: file, line: line
        )
    }

    // MARK: - Blocks

    func testHeadingsParseToLevelsNotSyntax() {
        let document = MarkdownDocumentParser.parse("# One\n\n### Three")
        XCTAssertEqual(document.blocks.count, 2)

        guard case .heading(let level, let content) = document.blocks[0].content else {
            return XCTFail("Expected a heading")
        }
        XCTAssertEqual(level, 1)
        XCTAssertEqual(content.plainText, "One", "The # must not survive into the text")

        guard case .heading(let deeper, _) = document.blocks[1].content else {
            return XCTFail("Expected a heading")
        }
        XCTAssertEqual(deeper, 3)

        // A hashtag is not a heading.
        guard case .paragraph = MarkdownDocumentParser.parse("#hashtag").blocks[0].content else {
            return XCTFail("#hashtag must stay a paragraph")
        }
    }

    func testInlineStylesBecomeAttributesNotCharacters() {
        let document = MarkdownDocumentParser.parse("This is **important** and *soft* and `code`.")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }

        XCTAssertEqual(
            text.plainText,
            "This is important and soft and code.",
            "Syntax characters must be consumed, not shown"
        )

        let bold = text.runs.first { $0.style.contains(.bold) }
        XCTAssertEqual(bold?.text, "important")
        let italic = text.runs.first { $0.style.contains(.italic) }
        XCTAssertEqual(italic?.text, "soft")
        let code = text.runs.first { $0.style.contains(.code) }
        XCTAssertEqual(code?.text, "code")
    }

    func testNestedEmphasisCombinesStyles() {
        let document = MarkdownDocumentParser.parse("***both*** and **bold with *inner* text**")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }

        let both = text.runs.first { $0.text == "both" }
        XCTAssertEqual(both?.style, [.bold, .italic])

        let inner = text.runs.first { $0.text == "inner" }
        XCTAssertEqual(inner?.style, [.bold, .italic], "Inner emphasis inherits the outer style")
    }

    func testLinksCarryTheirDestination() {
        let document = MarkdownDocumentParser.parse("See [the docs](https://example.com/a(b)) now.")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(text.plainText, "See the docs now.")

        let link = text.runs.first { $0.link != nil }
        XCTAssertEqual(link?.text, "the docs")
        XCTAssertEqual(link?.link, "https://example.com/a(b)", "Balanced parens inside a URL must survive")
    }

    func testListsBecomeItemsWithStyle() {
        let bulleted = MarkdownDocumentParser.parse("- one\n- two")
        guard case .list(let style, let items) = bulleted.blocks[0].content else {
            return XCTFail("Expected a list")
        }
        XCTAssertEqual(style, .bulleted)
        XCTAssertEqual(items.map(\.content.plainText), ["one", "two"])

        let ordered = MarkdownDocumentParser.parse("3. three\n4. four")
        guard case .list(.ordered(let start), let orderedItems) = ordered.blocks[0].content else {
            return XCTFail("Expected an ordered list")
        }
        XCTAssertEqual(start, 3, "An ordered list keeps the number it started at")
        XCTAssertEqual(orderedItems.count, 2)

        // A task list is a bulleted list whose items carry a checkbox — not a
        // separate kind of list, which is what Markdown can actually express.
        let tasks = MarkdownDocumentParser.parse("- [ ] todo\n- [x] done\n- plain")
        guard case .list(.bulleted, let taskItems) = tasks.blocks[0].content else {
            return XCTFail("Expected a bulleted list")
        }
        XCTAssertEqual(taskItems.map(\.checkbox), [false, true, nil])
        XCTAssertEqual(taskItems[1].content.plainText, "done")

        // Checkboxes work after an ordered marker too.
        let orderedTasks = MarkdownDocumentParser.parse("1. [x] done")
        guard case .list(.ordered, let orderedTaskItems) = orderedTasks.blocks[0].content else {
            return XCTFail("Expected an ordered list")
        }
        XCTAssertEqual(orderedTaskItems[0].checkbox, true)
        XCTAssertEqual(orderedTaskItems[0].content.plainText, "done")
    }

    func testTableBecomesRowsAndCells() {
        let document = MarkdownDocumentParser.parse("""
        | Name | Age |
        | :--- | ---: |
        | Ada | 36 |
        | Alan | 41 |
        """)

        guard case .table(let table) = document.blocks[0].content else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(table.columnCount, 2)
        XCTAssertEqual(table.alignments, [.left, .right])
        XCTAssertEqual(table.header.cells.map(\.content.plainText), ["Name", "Age"])
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[1].cells.map(\.content.plainText), ["Alan", "41"])
    }

    func testRaggedTableIsNormalisedToItsColumnCount() {
        let document = MarkdownDocumentParser.parse("""
        | A | B | C |
        | --- | --- | --- |
        | only one |
        """)
        guard case .table(let table) = document.blocks[0].content else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows[0].cells.count, 3, "Short rows are padded, never left ragged")
    }

    func testCodeBlockKeepsItsTextVerbatim() {
        let document = MarkdownDocumentParser.parse("```swift\nlet x = **not bold**\n```")
        guard case .code(let language, let text) = document.blocks[0].content else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(language, "swift")
        XCTAssertEqual(text, "let x = **not bold**", "Code is never inline-parsed")
    }

    func testQuoteHoldsBlocksNotText() {
        let document = MarkdownDocumentParser.parse("> ## Inside\n>\n> A paragraph.")
        guard case .quote(let blocks) = document.blocks[0].content else {
            return XCTFail("Expected a quote")
        }
        XCTAssertEqual(blocks.count, 2)
        guard case .heading = blocks[0].content else {
            return XCTFail("A quote can contain a heading")
        }
    }

    func testUnknownHTMLSurvivesVerbatim() {
        let source = "<div dir=\"rtl\" markdown=\"1\">\n<span>x</span>\n</div>"
        let document = MarkdownDocumentParser.parse(source)
        guard case .raw(let text) = document.blocks[0].content else {
            return XCTFail("Unrecognised HTML must be preserved, not dropped")
        }
        XCTAssertEqual(text, source)
    }

    // MARK: - Round trips

    func testRoundTripsAcrossEveryBlockKind() {
        assertRoundTrips("# Title\n\nA paragraph.")
        assertRoundTrips("Plain text only.")
        assertRoundTrips("- one\n- two\n- three")
        assertRoundTrips("1. first\n2. second")
        assertRoundTrips("- [ ] todo\n- [x] done")
        assertRoundTrips("> quoted text\n\nafter")
        assertRoundTrips("```python\nprint(1)\n```")
        assertRoundTrips("| A | B |\n| --- | :---: |\n| 1 | 2 |")
        assertRoundTrips("---")
        assertRoundTrips("Text with **bold**, *italic*, ~~struck~~, `code`.")
        assertRoundTrips("A [link](https://example.com) here.")
        assertRoundTrips("<div dir=\"rtl\" markdown=\"1\">\ncontent\n</div>")
    }

    func testRoundTripsARealisticDocument() {
        assertRoundTrips("""
        # Project README

        One sentence on what this does, with **bold** and a [link](https://example.com).

        ## Installation

        ```bash
        brew install thing
        ```

        ## Notes

        - First point
        - Second point with `code`
        - [x] Done item

        > A quoted aside.

        | Option | Default | Notes |
        | :--- | ---: | :---: |
        | `--fast` | off | experimental |

        ---

        Final paragraph.
        """)
    }

    func testRoundTripsPersianAndMixedDirectionText() {
        assertRoundTrips("""
        # عنوان سند

        متن فارسی با **پررنگ** و یک [پیوند](https://example.com) در میان.

        - مورد اول
        - مورد دوم

        | ستون ۱ | ستون ۲ |
        | --- | --- |
        | مقدار | value |
        """)
    }

    func testCharactersThatLookLikeSyntaxSurviveRoundTrip() {
        // Literal asterisks and underscores must come back as themselves.
        let document = MarkdownDocumentParser.parse("a \\* b \\_ c")
        guard case .paragraph(let text) = document.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(text.plainText, "a * b _ c")

        let written = MarkdownDocumentSerializer.serialize(document)
        let reparsed = MarkdownDocumentParser.parse(written)
        guard case .paragraph(let again) = reparsed.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(again.plainText, "a * b _ c", "Escaping must survive a save/open cycle")
    }

    func testPipeInATableCellSurvivesRoundTrip() {
        let table = TableBlock(
            header: TableRow(cells: [TableCell(content: InlineText(plain: "Pattern"))]),
            rows: [TableRow(cells: [TableCell(content: InlineText(plain: "a|b"))])],
            alignments: [.none]
        )
        let document = RichDocument(blocks: [RichBlock(content: .table(table))])

        let written = MarkdownDocumentSerializer.serialize(document)
        let reparsed = MarkdownDocumentParser.parse(written)

        guard case .table(let result) = reparsed.blocks[0].content else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(result.columnCount, 1, "An escaped pipe must not split the cell")
    }

    func testBackticksInsideCodeGetALongerFence() {
        let document = RichDocument(blocks: [
            RichBlock(content: .code(language: nil, text: "``` not the end"))
        ])
        let written = MarkdownDocumentSerializer.serialize(document)
        let reparsed = MarkdownDocumentParser.parse(written)

        guard case .code(_, let text) = reparsed.blocks[0].content else {
            return XCTFail("Expected a code block")
        }
        XCTAssertEqual(text, "``` not the end")
    }

    func testEmptyDocumentSerialisesToNothing() {
        XCTAssertEqual(MarkdownDocumentSerializer.serialize(RichDocument(blocks: [])), "")
        XCTAssertTrue(MarkdownDocumentParser.parse("").blocks.isEmpty)
        XCTAssertTrue(RichDocument.empty.isEmpty)
    }

    func testInlineRunsAreMergedRatherThanFragmented() {
        var text = InlineText([
            InlineRun("a"), InlineRun("b"), InlineRun("c", style: .bold), InlineRun("d", style: .bold)
        ])
        text.normalize()
        XCTAssertEqual(text.runs.count, 2, "Adjacent runs sharing a style must merge")
        XCTAssertEqual(text.runs[0].text, "ab")
        XCTAssertEqual(text.runs[1].text, "cd")
    }

    func testBlockIdentityIsStableAcrossEdits() {
        var document = MarkdownDocumentParser.parse("# One\n\nTwo")
        let headingID = document.blocks[0].id

        // Editing a later block must not disturb the identity of an earlier one
        // — the AI and undo both address blocks by id.
        document.blocks[1].content = .paragraph(InlineText(plain: "Changed"))
        XCTAssertEqual(document.blocks[0].id, headingID)
        XCTAssertEqual(document.index(of: headingID), 0)
    }

    // MARK: - Corpus and property tests

    /// Hand-written cases only cover what I thought to write down. These two
    /// cover what I didn't.
    func testRoundTripsTheRepositoryCorpus() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let corpus = root.appendingPathComponent("TestDocuments")

        let files = (try? FileManager.default.contentsOfDirectory(at: corpus, includingPropertiesForKeys: nil))?
            .filter { ["md", "markdown"].contains($0.pathExtension.lowercased()) } ?? []

        XCTAssertFalse(files.isEmpty, "Expected Markdown documents in TestDocuments/")

        for file in files {
            let markdown = try String(contentsOf: file, encoding: .utf8)
            assertRoundTrips(markdown)
        }
    }

    func testRoundTripsEveryStarterTemplate() {
        for template in DocumentTemplate.all {
            assertRoundTrips(template.body)
        }
    }

    /// Generates documents from the model itself, so the test explores shapes
    /// no hand-written sample would.
    func testGeneratedDocumentsSurviveSerialization() {
        var generator = SystemRandomNumberGenerator()

        for iteration in 0..<300 {
            // Generated through the model's own invariant, which is what the
            // editor is allowed to produce.
            let document = Self.randomDocument(using: &generator).normalized()
            let written = MarkdownDocumentSerializer.serialize(document)
            let reparsed = MarkdownDocumentParser.parse(written)

            XCTAssertTrue(
                document.hasSameContent(as: reparsed),
                """
                Generated document did not survive a round trip (iteration \(iteration)).
                written:  \(written.debugDescription)
                expected: \(document.blocks.map(\.content))
                actual:   \(reparsed.blocks.map(\.content))
                """
            )
        }
    }

    private static let words = [
        "alpha", "beta", "gamma", "delta", "متن", "فارسی", "value", "note",
        "x", "a b", "one two three", "café", "naïve", "طولانی‌تر"
    ]

    private static func randomInline(using generator: inout SystemRandomNumberGenerator) -> InlineText {
        var runs: [InlineRun] = []
        for _ in 0..<Int.random(in: 1...3, using: &generator) {
            let styles: [InlineStyle] = [[], .bold, .italic, .code, .strikethrough, [.bold, .italic]]
            let style = styles.randomElement(using: &generator)!
            let text = words.randomElement(using: &generator)!
            // A link on a code run is legal but rare; keep the generator honest
            // about what the editor can produce.
            let link = Bool.random(using: &generator) ? nil : "https://example.com/\(Int.random(in: 1...99, using: &generator))"
            runs.append(InlineRun(text, style: style, link: link))
        }
        return InlineText(runs).normalized()
    }

    private static func randomDocument(using generator: inout SystemRandomNumberGenerator) -> RichDocument {
        var blocks: [RichBlock] = []

        for _ in 0..<Int.random(in: 1...6, using: &generator) {
            switch Int.random(in: 0...6, using: &generator) {
            case 0:
                blocks.append(RichBlock(content: .paragraph(randomInline(using: &generator))))
            case 1:
                blocks.append(RichBlock(content: .heading(
                    level: Int.random(in: 1...6, using: &generator),
                    content: randomInline(using: &generator)
                )))
            case 2:
                let styles: [ListStyle] = [.bulleted, .ordered(start: Int.random(in: 1...5, using: &generator))]
                let style = styles.randomElement(using: &generator)!
                let checkboxes: [Bool?] = [nil, true, false]
                let items = (0..<Int.random(in: 1...4, using: &generator)).map { _ in
                    ListItem(
                        content: randomInline(using: &generator),
                        indent: Int.random(in: 0...2, using: &generator),
                        checkbox: checkboxes.randomElement(using: &generator)!
                    )
                }
                blocks.append(RichBlock(content: .list(style: style, items: items)))
            case 3:
                let columns = Int.random(in: 1...4, using: &generator)
                let alignments = (0..<columns).map { _ in TableColumnAlignment.allCases.randomElement(using: &generator)! }
                let header = TableRow(cells: (0..<columns).map { _ in TableCell(content: randomInline(using: &generator)) })
                let rows = (0..<Int.random(in: 0...3, using: &generator)).map { _ in
                    TableRow(cells: (0..<columns).map { _ in TableCell(content: randomInline(using: &generator)) })
                }
                var table = TableBlock(header: header, rows: rows, alignments: alignments)
                table.normalize()
                blocks.append(RichBlock(content: .table(table)))
            case 4:
                blocks.append(RichBlock(content: .code(
                    language: Bool.random(using: &generator) ? "swift" : nil,
                    text: words.randomElement(using: &generator)!
                )))
            case 5:
                blocks.append(RichBlock(content: .divider))
            default:
                blocks.append(RichBlock(content: .quote(blocks: [
                    RichBlock(content: .paragraph(randomInline(using: &generator)))
                ])))
            }
        }
        return RichDocument(blocks: blocks)
    }

    /// Markdown cannot keep two adjacent bulleted lists apart — they come back
    /// as one. Rather than let a document hold a state that a save would
    /// destroy, normalisation merges them up front.
    func testAdjacentListsOfTheSameKindAreMerged() {
        let document = RichDocument(blocks: [
            RichBlock(content: .list(style: .bulleted, items: [ListItem(content: InlineText(plain: "a"))])),
            RichBlock(content: .list(style: .bulleted, items: [ListItem(content: InlineText(plain: "b"), checkbox: false)]))
        ]).normalized()

        XCTAssertEqual(document.blocks.count, 1)
        guard case .list(.bulleted, let items) = document.blocks[0].content else {
            return XCTFail("Expected one merged list")
        }
        XCTAssertEqual(items.map(\.content.plainText), ["a", "b"])
        XCTAssertEqual(items.map(\.checkbox), [nil, false])

        // Different kinds stay apart, because Markdown keeps them apart.
        let mixed = RichDocument(blocks: [
            RichBlock(content: .list(style: .bulleted, items: [ListItem(content: InlineText(plain: "a"))])),
            RichBlock(content: .list(style: .ordered(start: 1), items: [ListItem(content: InlineText(plain: "b"))]))
        ]).normalized()
        XCTAssertEqual(mixed.blocks.count, 2)
    }

    func testHeadingLevelsAreClampedToWhatMarkdownAllows() {
        let block = RichBlock(content: .heading(level: 99, content: InlineText(plain: "x"))).normalized()
        guard case .heading(let level, _) = block.content else { return XCTFail("Expected a heading") }
        XCTAssertEqual(level, 6)
    }

    // MARK: - Operations

    private func parsed(_ markdown: String) -> RichDocument {
        MarkdownDocumentParser.parse(markdown)
    }

    func testReplacingOneBlockLeavesEveryOtherBlockUntouched() throws {
        let document = parsed("# Title\n\nFirst paragraph.\n\nSecond paragraph.")
        let target = document.blocks[1].id
        let untouched = document.blocks[2]

        let updated = try document.applying(
            .replaceInline(block: target, content: InlineText(plain: "Shorter."))
        )

        XCTAssertEqual(updated.blocks.count, 3)
        XCTAssertEqual(updated.blocks[1].plainText, "Shorter.")
        XCTAssertEqual(updated.blocks[0].plainText, "Title", "The heading must not move or change")
        XCTAssertEqual(updated.blocks[2], untouched, "An unrelated block must be byte-identical")
        XCTAssertEqual(updated.blocks[1].id, target, "The block keeps its identity across an edit")
    }

    func testAddressingADeletedBlockIsAnError() {
        let document = parsed("A paragraph.")
        XCTAssertThrowsError(
            try document.applying(.replaceInline(block: UUID(), content: InlineText(plain: "x")))
        ) { error in
            guard case DocumentOperationError.unknownBlock = error else {
                return XCTFail("Expected unknownBlock, got \(error)")
            }
        }
    }

    func testSetStyleAppliesToACharacterRangeAndSplitsRuns() throws {
        let document = parsed("make this bold")
        let block = document.blocks[0].id

        // "this" is characters 5..<9 of the rendered text.
        let updated = try document.applying(
            .setStyle(block: block, range: 5..<9, style: .bold, enabled: true)
        )
        guard case .paragraph(let text) = updated.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }

        XCTAssertEqual(text.plainText, "make this bold", "Styling must not change the text")
        XCTAssertEqual(text.runs.count, 3)
        XCTAssertEqual(text.runs[1].text, "this")
        XCTAssertTrue(text.runs[1].style.contains(.bold))
        XCTAssertFalse(text.runs[0].style.contains(.bold))

        // And it serialises to the Markdown a person would expect.
        XCTAssertEqual(
            MarkdownDocumentSerializer.serialize(updated).trimmingCharacters(in: .newlines),
            "make **this** bold"
        )

        // Turning it off again restores a single run.
        let cleared = try updated.applying(
            .setStyle(block: block, range: 5..<9, style: .bold, enabled: false)
        )
        guard case .paragraph(let restored) = cleared.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
        XCTAssertEqual(restored.runs.count, 1, "Runs must merge back down, not stay fragmented")
    }

    func testHeadingLevelAndParagraphConversion() throws {
        let document = parsed("Just text.")
        let block = document.blocks[0].id

        let heading = try document.applying(.setHeadingLevel(block: block, level: 2))
        guard case .heading(let level, _) = heading.blocks[0].content else {
            return XCTFail("Expected a heading")
        }
        XCTAssertEqual(level, 2)

        let back = try heading.applying(.setHeadingLevel(block: block, level: 0))
        guard case .paragraph = back.blocks[0].content else {
            return XCTFail("Level 0 returns the block to body text")
        }
    }

    func testConvertToListAndBack() throws {
        let document = parsed("One line.")
        let block = document.blocks[0].id

        let list = try document.applying(.convertToList(block: block, style: .bulleted))
        guard case .list(.bulleted, let items) = list.blocks[0].content else {
            return XCTFail("Expected a list")
        }
        XCTAssertEqual(items.map(\.content.plainText), ["One line."])

        let paragraphs = try list.applying(.convertToParagraph(block: block))
        XCTAssertEqual(paragraphs.blocks.count, 1)
        guard case .paragraph = paragraphs.blocks[0].content else {
            return XCTFail("Expected a paragraph")
        }
    }

    func testCheckboxToggleFindsItsItem() throws {
        let document = parsed("- [ ] one\n- [ ] two")
        let block = document.blocks[0].id
        guard case .list(_, let items) = document.blocks[0].content else {
            return XCTFail("Expected a list")
        }

        let updated = try document.applying(
            .setCheckbox(block: block, item: items[1].id, checked: true)
        )
        guard case .list(_, let updatedItems) = updated.blocks[0].content else {
            return XCTFail("Expected a list")
        }
        XCTAssertEqual(updatedItems.map(\.checkbox), [false, true])
    }

    func testBlockInsertionDeletionAndMove() throws {
        let document = parsed("# A\n\nB\n\nC")
        let first = document.blocks[0].id
        let last = document.blocks[2].id

        let inserted = try document.applying(
            .insertBlock(RichBlock(content: .paragraph(InlineText(plain: "new"))), after: first)
        )
        XCTAssertEqual(inserted.blocks.map(\.plainText), ["A", "new", "B", "C"])

        let moved = try inserted.applying(.moveBlock(last, toIndex: 0))
        XCTAssertEqual(moved.blocks.map(\.plainText), ["C", "A", "new", "B"])

        let deleted = try moved.applying(.deleteBlock(last))
        XCTAssertEqual(deleted.blocks.map(\.plainText), ["A", "new", "B"])
    }

    func testTableOperationsMutateTheObjectNotItsText() throws {
        let document = parsed("| A | B |\n| --- | --- |\n| 1 | 2 |")
        let block = document.blocks[0].id

        var updated = try document.applying(.setCell(
            block: block, row: 1, column: 0, content: InlineText(plain: "changed")
        ))
        updated = try updated.applying(.insertTableRow(block: block, at: 1))
        updated = try updated.applying(.insertTableColumn(block: block, at: 2))
        updated = try updated.applying(.setColumnAlignment(block: block, column: 1, alignment: .center))

        guard case .table(let table) = updated.blocks[0].content else {
            return XCTFail("Expected a table")
        }
        XCTAssertEqual(table.columnCount, 3)
        XCTAssertEqual(table.rows.count, 2)
        XCTAssertEqual(table.rows[0].cells[0].content.plainText, "changed")
        XCTAssertEqual(table.alignments[1], .center)
        // Every row keeps the table's width — no ragged rows, ever.
        XCTAssertTrue(([table.header] + table.rows).allSatisfy { $0.cells.count == 3 })

        // And it still round-trips.
        assertRoundTrips(MarkdownDocumentSerializer.serialize(updated))
    }

    func testDeletingTheLastTableColumnIsRefused() throws {
        let document = parsed("| A |\n| --- |\n| 1 |")
        let block = document.blocks[0].id
        XCTAssertThrowsError(try document.applying(.deleteTableColumn(block: block, at: 0)))
    }

    func testTableOperationOnAParagraphIsAnError() {
        let document = parsed("Not a table.")
        let block = document.blocks[0].id
        XCTAssertThrowsError(try document.applying(.insertTableRow(block: block, at: 0))) { error in
            guard case DocumentOperationError.wrongBlockKind = error else {
                return XCTFail("Expected wrongBlockKind, got \(error)")
            }
        }
    }

    func testABatchThatFailsPartWayLeavesTheDocumentUntouched() {
        let document = parsed("# Title\n\nBody")
        let valid = document.blocks[0].id

        let batch: [DocumentOperation] = [
            .setHeadingLevel(block: valid, level: 3),
            .replaceInline(block: UUID(), content: InlineText(plain: "boom"))
        ]

        XCTAssertThrowsError(try document.applying(batch))
        // The caller keeps the original, so a half-applied edit can't exist.
        XCTAssertEqual(document.blocks[0].plainText, "Title")
        guard case .heading(let level, _) = document.blocks[0].content else {
            return XCTFail("Expected a heading")
        }
        XCTAssertEqual(level, 1)
    }

    func testOperationsPreserveRoundTripping() throws {
        var document = parsed("""
        # Notes

        A paragraph with **bold**.

        - one
        - two
        """)

        let heading = document.blocks[0].id
        let paragraph = document.blocks[1].id

        document = try document.applying([
            .setHeadingLevel(block: heading, level: 3),
            .setStyle(block: paragraph, range: 0..<1, style: .italic, enabled: true),
            .insertBlock(RichBlock(content: .divider), after: paragraph)
        ])

        assertRoundTrips(MarkdownDocumentSerializer.serialize(document))
    }
}
