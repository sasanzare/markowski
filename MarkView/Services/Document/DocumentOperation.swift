import Foundation

/// A single, addressable change to the document.
///
/// This is what the editor and the assistant both speak. "Make this paragraph
/// shorter" becomes `.replaceInline(block:…)` against one block id — not a
/// regenerated file — so the change is local, reviewable, undoable, and can be
/// applied without disturbing anything else in the document.
enum DocumentOperation: Equatable {
    // Text
    case replaceInline(block: UUID, content: InlineText)
    case setStyle(block: UUID, range: Range<Int>, style: InlineStyle, enabled: Bool)
    case setLink(block: UUID, range: Range<Int>, destination: String?)

    // Blocks
    case setHeadingLevel(block: UUID, level: Int)
    case convertToParagraph(block: UUID)
    case convertToList(block: UUID, style: ListStyle)
    case setCheckbox(block: UUID, item: UUID, checked: Bool?)
    /// Replaces one block with whatever the replacement parses to — usually
    /// one block, sometimes several. This is the operation the assistant
    /// reaches for most: rewrite *this* paragraph, leave the file alone.
    case replaceBlock(UUID, with: [RichBlock])
    case insertBlock(RichBlock, after: UUID?)
    case deleteBlock(UUID)
    case moveBlock(UUID, toIndex: Int)

    // Tables
    case setCell(block: UUID, row: Int, column: Int, content: InlineText)
    case insertTableRow(block: UUID, at: Int)
    case deleteTableRow(block: UUID, at: Int)
    case insertTableColumn(block: UUID, at: Int)
    case deleteTableColumn(block: UUID, at: Int)
    case setColumnAlignment(block: UUID, column: Int, alignment: TableColumnAlignment)
}

enum DocumentOperationError: LocalizedError, Equatable {
    case unknownBlock(UUID)
    case wrongBlockKind(expected: String)
    case indexOutOfRange

    var errorDescription: String? {
        switch self {
        case .unknownBlock:
            return "That block is no longer in the document."
        case .wrongBlockKind(let expected):
            return "That operation only applies to a \(expected)."
        case .indexOutOfRange:
            return "That row or column doesn’t exist."
        }
    }
}

extension RichDocument {

    /// Applies one operation, returning the new document.
    ///
    /// Throwing rather than silently no-op'ing matters: an assistant addressing
    /// a block that has since been deleted should surface that, not quietly do
    /// nothing.
    func applying(_ operation: DocumentOperation) throws -> RichDocument {
        var document = self

        switch operation {
        case .replaceInline(let blockID, let content):
            try document.mutateInline(blockID) { $0 = content.normalized() }

        case .setStyle(let blockID, let range, let style, let enabled):
            try document.mutateInline(blockID) {
                $0 = InlineTextEditor.setStyle(style, enabled: enabled, in: $0, range: range)
            }

        case .setLink(let blockID, let range, let destination):
            try document.mutateInline(blockID) {
                $0 = InlineTextEditor.setLink(destination, in: $0, range: range)
            }

        case .setHeadingLevel(let blockID, let level):
            let index = try document.requireIndex(blockID)
            let content = document.blocks[index].content
            let text: InlineText
            switch content {
            case .heading(_, let existing): text = existing
            case .paragraph(let existing): text = existing
            default: throw DocumentOperationError.wrongBlockKind(expected: "paragraph or heading")
            }
            document.blocks[index].content = level <= 0
                ? .paragraph(text)
                : .heading(level: min(level, 6), content: text)

        case .convertToParagraph(let blockID):
            let index = try document.requireIndex(blockID)
            let block = document.blocks[index]
            switch block.content {
            case .heading(_, let text):
                document.blocks[index].content = .paragraph(text)
            case .list(_, let items):
                // Each item becomes its own paragraph, in place.
                let paragraphs = items.map { RichBlock(content: .paragraph($0.content)) }
                document.blocks.replaceSubrange(index...index, with: paragraphs)
            case .quote(let blocks):
                document.blocks.replaceSubrange(index...index, with: blocks)
            default:
                document.blocks[index].content = .paragraph(InlineText(plain: block.plainText))
            }

        case .convertToList(let blockID, let style):
            let index = try document.requireIndex(blockID)
            let block = document.blocks[index]
            let items: [ListItem]
            switch block.content {
            case .paragraph(let text), .heading(_, let text):
                items = [ListItem(content: text)]
            case .list(_, let existing):
                items = existing
            default:
                throw DocumentOperationError.wrongBlockKind(expected: "paragraph, heading, or list")
            }
            document.blocks[index].content = .list(style: style, items: items)

        case .setCheckbox(let blockID, let itemID, let checked):
            let index = try document.requireIndex(blockID)
            guard case .list(let style, var items) = document.blocks[index].content else {
                throw DocumentOperationError.wrongBlockKind(expected: "list")
            }
            guard let itemIndex = items.firstIndex(where: { $0.id == itemID }) else {
                throw DocumentOperationError.indexOutOfRange
            }
            items[itemIndex].checkbox = checked
            document.blocks[index].content = .list(style: style, items: items)

        case .replaceBlock(let blockID, let replacement):
            let index = try document.requireIndex(blockID)
            guard !replacement.isEmpty else {
                document.blocks.remove(at: index)
                break
            }
            // The first replacement keeps the original's identity, so undo and
            // any later operation addressing it still land.
            var blocks = replacement
            blocks[0].id = blockID
            document.blocks.replaceSubrange(index...index, with: blocks)

        case .insertBlock(let block, let after):
            if let after {
                let index = try document.requireIndex(after)
                document.blocks.insert(block, at: index + 1)
            } else {
                document.blocks.insert(block, at: 0)
            }

        case .deleteBlock(let blockID):
            let index = try document.requireIndex(blockID)
            document.blocks.remove(at: index)

        case .moveBlock(let blockID, let target):
            let index = try document.requireIndex(blockID)
            let block = document.blocks.remove(at: index)
            document.blocks.insert(block, at: max(0, min(target, document.blocks.count)))

        case .setCell(let blockID, let row, let column, let content):
            try document.mutateTable(blockID) { table in
                let rows = [table.header] + table.rows
                guard row >= 0, row < rows.count, column >= 0, column < table.columnCount else {
                    throw DocumentOperationError.indexOutOfRange
                }
                if row == 0 {
                    table.header.cells[column].content = content.normalized()
                } else {
                    table.rows[row - 1].cells[column].content = content.normalized()
                }
            }

        case .insertTableRow(let blockID, let at):
            try document.mutateTable(blockID) { table in
                let cells = (0..<table.columnCount).map { _ in TableCell() }
                let target = max(0, min(at, table.rows.count))
                table.rows.insert(TableRow(cells: cells), at: target)
            }

        case .deleteTableRow(let blockID, let at):
            try document.mutateTable(blockID) { table in
                guard at >= 0, at < table.rows.count else {
                    throw DocumentOperationError.indexOutOfRange
                }
                table.rows.remove(at: at)
            }

        case .insertTableColumn(let blockID, let at):
            try document.mutateTable(blockID) { table in
                let target = max(0, min(at, table.columnCount))
                table.alignments.insert(.none, at: target)
                table.header.cells.insert(TableCell(), at: min(target, table.header.cells.count))
                for index in table.rows.indices {
                    table.rows[index].cells.insert(TableCell(), at: min(target, table.rows[index].cells.count))
                }
            }

        case .deleteTableColumn(let blockID, let at):
            try document.mutateTable(blockID) { table in
                guard at >= 0, at < table.columnCount, table.columnCount > 1 else {
                    throw DocumentOperationError.indexOutOfRange
                }
                table.alignments.remove(at: at)
                table.header.cells.remove(at: at)
                for index in table.rows.indices where at < table.rows[index].cells.count {
                    table.rows[index].cells.remove(at: at)
                }
            }

        case .setColumnAlignment(let blockID, let column, let alignment):
            try document.mutateTable(blockID) { table in
                guard column >= 0, column < table.columnCount else {
                    throw DocumentOperationError.indexOutOfRange
                }
                table.alignments[column] = alignment
            }
        }

        return document.normalized()
    }

    /// Applies a batch as one unit. If any step fails the document is left
    /// untouched, so a partly-applied assistant edit is impossible.
    func applying(_ operations: [DocumentOperation]) throws -> RichDocument {
        var document = self
        for operation in operations {
            document = try document.applying(operation)
        }
        return document
    }

    // MARK: - Internals

    fileprivate func requireIndex(_ blockID: UUID) throws -> Int {
        guard let index = index(of: blockID) else {
            throw DocumentOperationError.unknownBlock(blockID)
        }
        return index
    }

    fileprivate mutating func mutateInline(
        _ blockID: UUID,
        _ transform: (inout InlineText) -> Void
    ) throws {
        let index = try requireIndex(blockID)

        switch blocks[index].content {
        case .paragraph(var text):
            transform(&text)
            blocks[index].content = .paragraph(text)
        case .heading(let level, var text):
            transform(&text)
            blocks[index].content = .heading(level: level, content: text)
        default:
            throw DocumentOperationError.wrongBlockKind(expected: "paragraph or heading")
        }
    }

    fileprivate mutating func mutateTable(
        _ blockID: UUID,
        _ transform: (inout TableBlock) throws -> Void
    ) throws {
        let index = try requireIndex(blockID)
        guard case .table(var table) = blocks[index].content else {
            throw DocumentOperationError.wrongBlockKind(expected: "table")
        }
        try transform(&table)
        table.normalize()
        blocks[index].content = .table(table)
    }
}

/// Character-range edits over styled runs.
///
/// Ranges are in *characters of the rendered text*, which is what a text view
/// and a person both mean by "this bit" — never offsets into Markdown syntax.
enum InlineTextEditor {

    static func setStyle(
        _ style: InlineStyle,
        enabled: Bool,
        in text: InlineText,
        range: Range<Int>
    ) -> InlineText {
        transform(text, range: range) { run in
            var updated = run
            if enabled {
                updated.style.formUnion(style)
            } else {
                updated.style.subtract(style)
            }
            return updated
        }
    }

    static func setLink(_ destination: String?, in text: InlineText, range: Range<Int>) -> InlineText {
        transform(text, range: range) { run in
            var updated = run
            updated.link = destination
            return updated
        }
    }

    /// Splits runs at the range boundaries, applies the transform to what falls
    /// inside, and merges the result back down.
    private static func transform(
        _ text: InlineText,
        range: Range<Int>,
        _ body: (InlineRun) -> InlineRun
    ) -> InlineText {
        guard !range.isEmpty else { return text }

        var result: [InlineRun] = []
        var offset = 0

        for run in text.runs {
            let characters = Array(run.text)
            let runRange = offset..<(offset + characters.count)
            offset = runRange.upperBound

            guard runRange.overlaps(range) else {
                result.append(run)
                continue
            }

            let localStart = max(range.lowerBound, runRange.lowerBound) - runRange.lowerBound
            let localEnd = min(range.upperBound, runRange.upperBound) - runRange.lowerBound

            if localStart > 0 {
                result.append(InlineRun(String(characters[0..<localStart]), style: run.style, link: run.link))
            }

            var inside = run
            inside.text = String(characters[localStart..<localEnd])
            result.append(body(inside))

            if localEnd < characters.count {
                result.append(InlineRun(String(characters[localEnd...]), style: run.style, link: run.link))
            }
        }

        return InlineText(result).normalized()
    }
}
