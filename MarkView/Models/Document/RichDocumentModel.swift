import Foundation

/// The document model — the source of truth for an open document.
///
/// Markdown is a *storage format* for this, not the thing being edited. The
/// editor mutates these blocks directly; Markdown is produced on save and
/// consumed on open. That inversion is what separates a rich-document editor
/// from a Markdown editor with a preview.

// MARK: - Inline content

struct InlineStyle: OptionSet, Hashable, Codable {
    let rawValue: Int

    static let bold = InlineStyle(rawValue: 1 << 0)
    static let italic = InlineStyle(rawValue: 1 << 1)
    static let code = InlineStyle(rawValue: 1 << 2)
    static let strikethrough = InlineStyle(rawValue: 1 << 3)
    static let highlight = InlineStyle(rawValue: 1 << 4)

    init(rawValue: Int) { self.rawValue = rawValue }
}

/// A stretch of text sharing one set of inline attributes. Styles live on the
/// text, not as syntax inside it, so `**` never appears in the editor.
struct InlineRun: Equatable, Codable {
    var text: String
    var style: InlineStyle
    /// Destination when this run is a link.
    var link: String?

    init(_ text: String, style: InlineStyle = [], link: String? = nil) {
        self.text = text
        self.style = style
        self.link = link
    }

    var isEmpty: Bool { text.isEmpty }
}

/// The inline content of one block-level element.
struct InlineText: Equatable, Codable {
    var runs: [InlineRun]

    init(_ runs: [InlineRun] = []) {
        self.runs = runs
    }

    init(plain text: String) {
        self.runs = text.isEmpty ? [] : [InlineRun(text)]
    }

    var plainText: String {
        runs.map(\.text).joined()
    }

    var isEmpty: Bool {
        runs.allSatisfy(\.isEmpty)
    }

    /// Merges adjacent runs that share formatting, so editing never leaves the
    /// model fragmented into hundreds of one-character runs.
    mutating func normalize() {
        var merged: [InlineRun] = []
        for run in runs where !run.isEmpty {
            if var last = merged.last, last.style == run.style, last.link == run.link {
                last.text += run.text
                merged[merged.count - 1] = last
            } else {
                merged.append(run)
            }
        }
        runs = merged
    }

    func normalized() -> InlineText {
        var copy = self
        copy.normalize()
        return copy
    }
}

// MARK: - Blocks

/// A task list is not a separate kind of list — it is a bulleted list whose
/// items carry a checkbox. Modelling it as its own style meant `- a` and
/// `- [ ] b` round-tripped into one list and then compared unequal, because
/// Markdown cannot keep two adjacent bulleted lists apart at all.
enum ListStyle: Equatable, Codable {
    case bulleted
    case ordered(start: Int)
}

struct ListItem: Equatable, Codable, Identifiable {
    var id: UUID
    var content: InlineText
    /// Nesting depth, 0 for a top-level item.
    var indent: Int
    /// `nil` for a plain item; `false`/`true` for an unchecked/checked task.
    var checkbox: Bool?

    init(id: UUID = UUID(), content: InlineText, indent: Int = 0, checkbox: Bool? = nil) {
        self.id = id
        self.content = content
        self.indent = indent
        self.checkbox = checkbox
    }

    var isTask: Bool { checkbox != nil }

    static func == (lhs: ListItem, rhs: ListItem) -> Bool {
        lhs.content == rhs.content && lhs.indent == rhs.indent && lhs.checkbox == rhs.checkbox
    }
}

enum TableColumnAlignment: String, Equatable, Codable, CaseIterable {
    case none, left, center, right
}

/// Where a cell's content sits within a row taller than itself.
enum TableVerticalAlignment: String, Equatable, Codable, CaseIterable {
    case top, middle, bottom
}

/// A table is a real object with rows and cells, not a block of pipe-delimited
/// text that has to be re-parsed on every keystroke.
///
/// The per-cell properties below are deliberately optional and default to
/// "nothing special". Markdown's table syntax can only express one alignment
/// per *column* and has no concept of a merged or vertically-aligned cell, so a
/// table that uses none of them still writes out as ordinary Markdown; only one
/// that actually needs more escalates to HTML. See `TableBlock.needsHTML`.
struct TableCell: Equatable, Codable, Identifiable {
    var id: UUID
    var content: InlineText
    /// Overrides the column's alignment for this cell alone. `nil` inherits.
    var horizontalAlignment: TableColumnAlignment?
    /// `nil` means the default, which is vertically centred.
    var verticalAlignment: TableVerticalAlignment?
    /// How many columns and rows this cell spans. 1 means an ordinary cell.
    var columnSpan: Int
    var rowSpan: Int
    /// True when a neighbouring cell's span covers this position.
    ///
    /// The grid is kept as a full rectangle with covered positions flagged,
    /// rather than as ragged rows. Every existing invariant — "each row has
    /// `columnCount` cells" — keeps holding, so layout, navigation, and
    /// normalisation did not have to learn about holes.
    var isCovered: Bool

    init(
        id: UUID = UUID(),
        content: InlineText = InlineText(),
        horizontalAlignment: TableColumnAlignment? = nil,
        verticalAlignment: TableVerticalAlignment? = nil,
        columnSpan: Int = 1,
        rowSpan: Int = 1,
        isCovered: Bool = false
    ) {
        self.id = id
        self.content = content
        self.horizontalAlignment = horizontalAlignment
        self.verticalAlignment = verticalAlignment
        self.columnSpan = columnSpan
        self.rowSpan = rowSpan
        self.isCovered = isCovered
    }

    /// Whether this cell needs more than Markdown's table syntax can say.
    var exceedsMarkdown: Bool {
        horizontalAlignment != nil
            || verticalAlignment != nil
            || columnSpan > 1
            || rowSpan > 1
            || isCovered
    }

    static func == (lhs: TableCell, rhs: TableCell) -> Bool {
        lhs.content == rhs.content
            && lhs.horizontalAlignment == rhs.horizontalAlignment
            && lhs.verticalAlignment == rhs.verticalAlignment
            && lhs.columnSpan == rhs.columnSpan
            && lhs.rowSpan == rhs.rowSpan
            && lhs.isCovered == rhs.isCovered
    }
}

struct TableRow: Equatable, Codable, Identifiable {
    var id: UUID
    var cells: [TableCell]

    init(id: UUID = UUID(), cells: [TableCell]) {
        self.id = id
        self.cells = cells
    }

    static func == (lhs: TableRow, rhs: TableRow) -> Bool {
        lhs.cells == rhs.cells
    }
}

struct TableBlock: Equatable, Codable {
    var header: TableRow
    var rows: [TableRow]
    var alignments: [TableColumnAlignment]

    var columnCount: Int { alignments.count }

    var allRows: [TableRow] { [header] + rows }

    /// Whether this table uses anything Markdown's table syntax cannot express.
    ///
    /// Markdown gives you one alignment per column and nothing else — no merged
    /// cells, no vertical alignment, no per-cell override. A table using any of
    /// those has to be written as HTML or it would be silently flattened on
    /// save. A table using none of them stays ordinary Markdown.
    var needsHTML: Bool {
        allRows.contains { $0.cells.contains(where: \.exceedsMarkdown) }
    }

    /// Every row is padded or trimmed to the column count, so the model can
    /// never describe a ragged table.
    mutating func normalize() {
        let width = max(1, alignments.count)
        alignments = Array(alignments.prefix(width))
        while alignments.count < width { alignments.append(.none) }

        header = Self.resize(header, to: width)
        rows = rows.map { Self.resize($0, to: width) }
        rebuildCoverage()
    }

    /// Recomputes which positions are covered by a span, and clips any span
    /// that would run off the edge of the table.
    ///
    /// Coverage is derived, never authored: deleting a row that a merge reached
    /// into would otherwise leave a cell claiming to span rows that no longer
    /// exist, and the grid would draw over its neighbours.
    mutating func rebuildCoverage() {
        let width = max(1, columnCount)
        var grid = allRows
        let height = grid.count

        for row in 0..<height {
            for column in 0..<width where column < grid[row].cells.count {
                grid[row].cells[column].isCovered = false
            }
        }

        var covered = Array(repeating: Array(repeating: false, count: width), count: height)
        for row in 0..<height {
            for column in 0..<width where column < grid[row].cells.count {
                if covered[row][column] {
                    grid[row].cells[column].isCovered = true
                    grid[row].cells[column].columnSpan = 1
                    grid[row].cells[column].rowSpan = 1
                    continue
                }

                let columnSpan = max(1, min(grid[row].cells[column].columnSpan, width - column))
                let rowSpan = max(1, min(grid[row].cells[column].rowSpan, height - row))
                grid[row].cells[column].columnSpan = columnSpan
                grid[row].cells[column].rowSpan = rowSpan

                for r in row..<(row + rowSpan) {
                    for c in column..<(column + columnSpan) where !(r == row && c == column) {
                        covered[r][c] = true
                    }
                }
            }
        }

        header = grid[0]
        rows = Array(grid.dropFirst())
    }

    /// The cell that actually owns a position — itself, or the spanning cell
    /// covering it.
    func anchor(forRow row: Int, column: Int) -> (row: Int, column: Int)? {
        let grid = allRows
        guard row >= 0, row < grid.count, column >= 0, column < columnCount else { return nil }
        guard grid[row].cells.indices.contains(column), grid[row].cells[column].isCovered else {
            return (row, column)
        }

        for r in stride(from: row, through: 0, by: -1) {
            for c in stride(from: column, through: 0, by: -1) {
                guard grid[r].cells.indices.contains(c) else { continue }
                let candidate = grid[r].cells[c]
                guard !candidate.isCovered else { continue }
                if r + candidate.rowSpan > row, c + candidate.columnSpan > column {
                    return (r, c)
                }
            }
        }
        return nil
    }

    private static func resize(_ row: TableRow, to width: Int) -> TableRow {
        var resized = row
        while resized.cells.count < width { resized.cells.append(TableCell()) }
        resized.cells = Array(resized.cells.prefix(width))
        return resized
    }
}

enum BlockContent: Equatable, Codable {
    case paragraph(InlineText)
    case heading(level: Int, content: InlineText)
    case list(style: ListStyle, items: [ListItem])
    case quote(blocks: [RichBlock])
    case code(language: String?, text: String)
    case table(TableBlock)
    case divider
    /// Anything the parser recognised but does not model — raw HTML, front
    /// matter — carried through verbatim so opening and saving is lossless.
    case raw(String)
}

/// A block carries a stable identity so the editor, the AI, and undo can all
/// refer to "that paragraph" across edits.
struct RichBlock: Equatable, Codable, Identifiable {
    var id: UUID
    var content: BlockContent

    init(id: UUID = UUID(), content: BlockContent) {
        self.id = id
        self.content = content
    }

    /// Identity addresses a block; it is not part of what the block *is*. Two
    /// blocks holding the same content are equal even after a save/open cycle
    /// has given them fresh ids.
    static func == (lhs: RichBlock, rhs: RichBlock) -> Bool {
        lhs.content == rhs.content
    }

    /// Forces the block into a state Markdown can actually express.
    ///
    /// A checked *bulleted* item, or a ragged table row, is representable in
    /// memory but not on disk — so it would be silently lost on save. Rather
    /// than let that happen, the model refuses to hold it.
    func normalized() -> RichBlock {
        var copy = self
        switch content {
        case .list(let style, let items):
            copy.content = .list(style: style, items: items.map { item in
                var normalizedItem = item
                normalizedItem.indent = max(0, min(item.indent, 6))
                normalizedItem.content = item.content.normalized()
                return normalizedItem
            })

        case .table(var table):
            table.normalize()
            copy.content = .table(table)

        case .quote(let blocks):
            copy.content = .quote(blocks: blocks.map { $0.normalized() })

        case .paragraph(let text):
            copy.content = .paragraph(text.normalized())

        case .heading(let level, let text):
            copy.content = .heading(level: min(max(level, 1), 6), content: text.normalized())

        case .code, .divider, .raw:
            break
        }
        return copy
    }

    var isEmptyParagraph: Bool {
        if case .paragraph(let text) = content { return text.isEmpty }
        return false
    }

    var plainText: String {
        switch content {
        case .paragraph(let text): return text.plainText
        case .heading(_, let text): return text.plainText
        case .list(_, let items): return items.map(\.content.plainText).joined(separator: "\n")
        case .quote(let blocks): return blocks.map(\.plainText).joined(separator: "\n")
        case .code(_, let text): return text
        case .table(let table):
            return ([table.header] + table.rows)
                .map { $0.cells.map(\.content.plainText).joined(separator: "\t") }
                .joined(separator: "\n")
        case .divider: return ""
        case .raw(let text): return text
        }
    }
}

/// The document itself.
struct RichDocument: Equatable, Codable {
    var blocks: [RichBlock]

    init(blocks: [RichBlock] = []) {
        self.blocks = blocks
    }

    static let empty = RichDocument(blocks: [RichBlock(content: .paragraph(InlineText()))])

    var isEmpty: Bool {
        blocks.isEmpty || blocks.allSatisfy(\.isEmptyParagraph)
    }

    /// Puts the document into the only shape Markdown can round-trip.
    ///
    /// Beyond per-block normalisation this merges adjacent lists of the same
    /// kind. Two bulleted lists separated by a blank line are indistinguishable
    /// from one list on the way back in, so holding them as two blocks is a
    /// state that cannot survive a save.
    func normalized() -> RichDocument {
        var result: [RichBlock] = []

        for block in blocks.map({ $0.normalized() }) {
            guard case .list(let style, let items) = block.content,
                  let previous = result.last,
                  case .list(let previousStyle, let previousItems) = previous.content,
                  Self.listsWouldMerge(previousStyle, style) else {
                result.append(block)
                continue
            }

            var merged = previous
            merged.content = .list(style: previousStyle, items: previousItems + items)
            result[result.count - 1] = merged
        }

        return RichDocument(blocks: result)
    }

    private static func listsWouldMerge(_ lhs: ListStyle, _ rhs: ListStyle) -> Bool {
        switch (lhs, rhs) {
        case (.bulleted, .bulleted): return true
        case (.ordered, .ordered): return true
        default: return false
        }
    }

    var plainText: String {
        blocks.map(\.plainText).joined(separator: "\n\n")
    }

    func index(of blockID: UUID) -> Int? {
        blocks.firstIndex { $0.id == blockID }
    }

    /// Comparison that ignores identity, for asserting that a round trip
    /// preserved *content* even though every block gets a fresh `id`.
    func hasSameContent(as other: RichDocument) -> Bool {
        guard blocks.count == other.blocks.count else { return false }
        return zip(blocks, other.blocks).allSatisfy { $0.content == $1.content }
    }
}
