import Foundation

/// The result of a formatting command: the whole new document plus where the
/// selection should end up. Returning both keeps the caller (a text view) from
/// having to re-derive the caret position after every transform.
struct MarkdownEdit: Equatable {
    let text: String
    let selectedRange: NSRange

    init(text: String, selectedRange: NSRange) {
        self.text = text
        self.selectedRange = selectedRange
    }
}

/// Every command the formatting panel can apply to Markdown source.
///
/// This is deliberately pure: it takes text and a UTF-16 range and returns new
/// text and a new range. Nothing here touches AppKit, so the whole surface is
/// unit-testable, and the same logic serves the source editor and the preview's
/// block editor.
enum MarkdownFormatter {

    // MARK: - Inline spans

    /// Wraps the selection in `marker`, or unwraps it when it is already
    /// wrapped — including the common case where the user selected the text
    /// *inside* existing markers.
    static func toggleInline(_ text: String, range: NSRange, marker: String) -> MarkdownEdit {
        let source = text as NSString
        let safeRange = clamp(range, in: source)
        let markerLength = (marker as NSString).length

        // Already wrapped, markers inside the selection: **|bold|**
        let selected = source.substring(with: safeRange)
        if selected.count >= marker.count * 2,
           selected.hasPrefix(marker),
           selected.hasSuffix(marker) {
            let inner = (selected as NSString).substring(
                with: NSRange(location: markerLength, length: (selected as NSString).length - markerLength * 2)
            )
            let updated = source.replacingCharacters(in: safeRange, with: inner)
            return MarkdownEdit(
                text: updated,
                selectedRange: NSRange(location: safeRange.location, length: (inner as NSString).length)
            )
        }

        // Already wrapped, markers outside the selection: **bold|selected|**
        let before = NSRange(location: safeRange.location - markerLength, length: markerLength)
        let after = NSRange(location: safeRange.upperBound, length: markerLength)
        if before.location >= 0,
           after.upperBound <= source.length,
           source.substring(with: before) == marker,
           source.substring(with: after) == marker {
            let outer = NSRange(location: before.location, length: markerLength * 2 + safeRange.length)
            let updated = source.replacingCharacters(in: outer, with: selected)
            return MarkdownEdit(
                text: updated,
                selectedRange: NSRange(location: before.location, length: safeRange.length)
            )
        }

        // Not wrapped yet. An empty selection gets the markers and a caret
        // between them, ready to type into.
        let wrapped = marker + selected + marker
        let updated = source.replacingCharacters(in: safeRange, with: wrapped)
        let newRange = safeRange.length == 0
            ? NSRange(location: safeRange.location + markerLength, length: 0)
            : NSRange(location: safeRange.location + markerLength, length: safeRange.length)
        return MarkdownEdit(text: updated, selectedRange: newRange)
    }

    // MARK: - Block prefixes

    /// Sets (or clears, with `level == 0`) the heading level of every line the
    /// selection touches.
    static func setHeading(_ text: String, range: NSRange, level: Int) -> MarkdownEdit {
        transformLines(text, range: range) { line in
            let stripped = stripHeading(from: line)
            guard level > 0 else { return stripped }
            return String(repeating: "#", count: min(level, 6)) + " " + stripped
        }
    }

    /// Toggles a simple line prefix — `> `, `- `, `- [ ] ` — across the
    /// selection. If every touched line already has it, it is removed.
    static func toggleLinePrefix(_ text: String, range: NSRange, prefix: String) -> MarkdownEdit {
        let lines = touchedLines(text, range: range)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allPrefixed = !nonEmpty.isEmpty && nonEmpty.allSatisfy {
            $0.trimmingCharacters(in: .whitespaces).hasPrefix(prefix.trimmingCharacters(in: .whitespaces))
        }

        return transformLines(text, range: range) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            if allPrefixed {
                return removePrefix(prefix, from: line)
            }
            return line.hasPrefix(prefix) ? line : prefix + removeAnyListPrefix(from: line)
        }
    }

    /// Numbers the touched lines, or unnumbers them when they already are.
    static func toggleOrderedList(_ text: String, range: NSRange) -> MarkdownEdit {
        let lines = touchedLines(text, range: range)
        let nonEmpty = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        let allNumbered = !nonEmpty.isEmpty && nonEmpty.allSatisfy { isOrderedItem($0) }

        var counter = 0
        return transformLines(text, range: range) { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return line }
            if allNumbered {
                return removeOrderedPrefix(from: line)
            }
            counter += 1
            return "\(counter). " + removeAnyListPrefix(from: line)
        }
    }

    // MARK: - Insertions

    static func insertLink(_ text: String, range: NSRange, url: String = "https://") -> MarkdownEdit {
        let source = text as NSString
        let safeRange = clamp(range, in: source)
        let label = source.substring(with: safeRange)
        let replacement = "[\(label.isEmpty ? "link text" : label)](\(url))"
        let updated = source.replacingCharacters(in: safeRange, with: replacement)

        // Land the selection on the URL — that is what still needs typing.
        let urlStart = safeRange.location + (replacement as NSString).range(of: url, options: .backwards).location
        return MarkdownEdit(
            text: updated,
            selectedRange: NSRange(location: urlStart, length: (url as NSString).length)
        )
    }

    static func insertHorizontalRule(_ text: String, range: NSRange) -> MarkdownEdit {
        insertBlock(text, range: range, block: "---")
    }

    static func insertCodeFence(_ text: String, range: NSRange, language: String = "") -> MarkdownEdit {
        let source = text as NSString
        let safeRange = clamp(range, in: source)
        let selected = source.substring(with: safeRange)
        let body = selected.isEmpty ? "" : selected
        return insertBlock(text, range: range, block: "```\(language)\n\(body)\n```")
    }

    static func insertTable(_ text: String, range: NSRange, rows: Int = 2, columns: Int = 3) -> MarkdownEdit {
        let safeColumns = max(1, columns)
        let safeRows = max(1, rows)

        let header = "| " + (1...safeColumns).map { "Column \($0)" }.joined(separator: " | ") + " |"
        let divider = "| " + Array(repeating: "---", count: safeColumns).joined(separator: " | ") + " |"
        let body = (0..<safeRows).map { _ in
            "| " + Array(repeating: " ", count: safeColumns).joined(separator: " | ") + " |"
        }

        return insertBlock(text, range: range, block: ([header, divider] + body).joined(separator: "\n"))
    }

    // MARK: - Direction

    enum BlockDirection: String {
        case rightToLeft = "rtl"
        case leftToRight = "ltr"
    }

    /// Markdown has no alignment syntax, so direction is expressed the way
    /// every Markdown renderer understands: an HTML wrapper. Applying it again
    /// with the same direction unwraps, so the button reads as a toggle.
    static func setBlockDirection(_ text: String, range: NSRange, direction: BlockDirection) -> MarkdownEdit {
        let source = text as NSString
        let lineRange = source.lineRange(for: clamp(range, in: source))
        var block = source.substring(with: lineRange)
        var trailingNewline = ""
        while block.hasSuffix("\n") {
            block.removeLast()
            trailingNewline += "\n"
        }

        let openTag = "<div dir=\"\(direction.rawValue)\" markdown=\"1\">"
        let closeTag = "</div>"

        if let unwrapped = unwrapDirection(block) {
            // Same direction → remove it. Different direction → re-wrap.
            if unwrapped.direction == direction {
                let replacement = unwrapped.body + trailingNewline
                return MarkdownEdit(
                    text: source.replacingCharacters(in: lineRange, with: replacement),
                    selectedRange: NSRange(location: lineRange.location, length: (unwrapped.body as NSString).length)
                )
            }
            block = unwrapped.body
        }

        let wrapped = "\(openTag)\n\(block)\n\(closeTag)" + trailingNewline
        return MarkdownEdit(
            text: source.replacingCharacters(in: lineRange, with: wrapped),
            selectedRange: NSRange(
                location: lineRange.location + (openTag as NSString).length + 1,
                length: (block as NSString).length
            )
        )
    }

    static func unwrapDirection(_ block: String) -> (direction: BlockDirection, body: String)? {
        let lines = block.components(separatedBy: "\n")
        guard lines.count >= 2,
              let first = lines.first?.trimmingCharacters(in: .whitespaces),
              let last = lines.last?.trimmingCharacters(in: .whitespaces),
              first.hasPrefix("<div"),
              last == "</div>" else {
            return nil
        }

        let direction: BlockDirection
        if first.contains("\"rtl\"") || first.contains("'rtl'") {
            direction = .rightToLeft
        } else if first.contains("\"ltr\"") || first.contains("'ltr'") {
            direction = .leftToRight
        } else {
            return nil
        }

        let body = lines.dropFirst().dropLast().joined(separator: "\n")
        return (direction, body)
    }

    // MARK: - Tables

    /// A GFM table found around a caret position, with its rows already split
    /// into cells.
    struct TableContext: Equatable {
        let range: NSRange
        var rows: [[String]]
        var alignments: [ColumnAlignment]
        /// Index into `rows` of the row the caret is on, header excluded.
        let caretRow: Int
        let caretColumn: Int

        var columnCount: Int { alignments.count }
    }

    enum ColumnAlignment: String, Equatable, CaseIterable {
        case none, left, center, right

        var dividerCell: String {
            switch self {
            case .none: return "---"
            case .left: return ":---"
            case .center: return ":---:"
            case .right: return "---:"
            }
        }
    }

    /// Finds the table the caret sits in, if any. Everything table-related is
    /// gated on this, so the panel can disable those controls when the caret
    /// isn't in a table.
    static func tableContext(in text: String, at location: Int) -> TableContext? {
        let source = text as NSString
        let lines = text.components(separatedBy: "\n")

        // Map each line index to its UTF-16 range.
        var lineRanges: [NSRange] = []
        var cursor = 0
        for line in lines {
            let length = (line as NSString).length
            lineRanges.append(NSRange(location: cursor, length: length))
            cursor += length + 1
        }

        let safeLocation = max(0, min(location, source.length))
        guard let caretLine = lineRanges.firstIndex(where: {
            safeLocation >= $0.location && safeLocation <= $0.upperBound
        }) else { return nil }

        guard isTableRow(lines[caretLine]) else { return nil }

        var start = caretLine
        while start > 0, isTableRow(lines[start - 1]) { start -= 1 }
        var end = caretLine
        while end < lines.count - 1, isTableRow(lines[end + 1]) { end += 1 }

        let tableLines = Array(lines[start...end])
        // A GFM table is a header, a divider, then body rows.
        guard tableLines.count >= 2, isDividerRow(tableLines[1]) else { return nil }

        let alignments = parseAlignments(tableLines[1])
        var rows = tableLines.enumerated()
            .filter { $0.offset != 1 }
            .map { splitRow($0.element, columns: alignments.count) }
        if rows.isEmpty { rows = [[]] }

        let caretRowIndex = caretLine < start + 2 ? 0 : caretLine - start - 1
        let caretColumnIndex = columnIndex(
            forLocation: safeLocation,
            lineRange: lineRanges[caretLine],
            line: lines[caretLine]
        )

        let tableRange = NSRange(
            location: lineRanges[start].location,
            length: lineRanges[end].upperBound - lineRanges[start].location
        )

        return TableContext(
            range: tableRange,
            rows: rows,
            alignments: alignments,
            caretRow: min(caretRowIndex, max(0, rows.count - 1)),
            caretColumn: min(caretColumnIndex, max(0, alignments.count - 1))
        )
    }

    static func render(_ table: TableContext) -> String {
        guard !table.rows.isEmpty else { return "" }

        var lines: [String] = []
        let width = table.columnCount

        func renderRow(_ cells: [String]) -> String {
            var padded = cells
            while padded.count < width { padded.append("") }
            return "| " + padded.prefix(width).map {
                $0.trimmingCharacters(in: .whitespaces).isEmpty ? " " : $0.trimmingCharacters(in: .whitespaces)
            }.joined(separator: " | ") + " |"
        }

        lines.append(renderRow(table.rows[0]))
        lines.append("| " + table.alignments.map(\.dividerCell).joined(separator: " | ") + " |")
        for row in table.rows.dropFirst() {
            lines.append(renderRow(row))
        }
        return lines.joined(separator: "\n")
    }

    static func addTableRow(_ text: String, at location: Int) -> MarkdownEdit? {
        guard var table = tableContext(in: text, at: location) else { return nil }
        let empty = Array(repeating: "", count: table.columnCount)
        table.rows.insert(empty, at: min(table.caretRow + 1, table.rows.count))
        return replaceTable(text, table: table)
    }

    static func addTableColumn(_ text: String, at location: Int) -> MarkdownEdit? {
        guard var table = tableContext(in: text, at: location) else { return nil }
        let insertAt = min(table.caretColumn + 1, table.columnCount)
        table.alignments.insert(.none, at: insertAt)
        table.rows = table.rows.enumerated().map { index, row in
            var updated = row
            while updated.count < insertAt { updated.append("") }
            updated.insert(index == 0 ? "Column \(insertAt + 1)" : "", at: insertAt)
            return updated
        }
        return replaceTable(text, table: table)
    }

    static func deleteTableRow(_ text: String, at location: Int) -> MarkdownEdit? {
        guard var table = tableContext(in: text, at: location), table.rows.count > 1 else { return nil }
        // Row 0 is the header; deleting it would destroy the table.
        guard table.caretRow > 0 else { return nil }
        table.rows.remove(at: table.caretRow)
        return replaceTable(text, table: table)
    }

    static func deleteTableColumn(_ text: String, at location: Int) -> MarkdownEdit? {
        guard var table = tableContext(in: text, at: location), table.columnCount > 1 else { return nil }
        let target = table.caretColumn
        table.alignments.remove(at: target)
        table.rows = table.rows.map { row in
            var updated = row
            if target < updated.count { updated.remove(at: target) }
            return updated
        }
        return replaceTable(text, table: table)
    }

    static func setTableColumnAlignment(
        _ text: String,
        at location: Int,
        alignment: ColumnAlignment
    ) -> MarkdownEdit? {
        guard var table = tableContext(in: text, at: location) else { return nil }
        table.alignments[table.caretColumn] = alignment
        return replaceTable(text, table: table)
    }

    private static func replaceTable(_ text: String, table: TableContext) -> MarkdownEdit {
        let source = text as NSString
        let rendered = render(table)
        return MarkdownEdit(
            text: source.replacingCharacters(in: table.range, with: rendered),
            selectedRange: NSRange(location: table.range.location, length: (rendered as NSString).length)
        )
    }

    private static func isTableRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        return trimmed.hasPrefix("|") && trimmed.count > 1
    }

    private static func isDividerRow(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard isTableRow(trimmed) else { return false }
        let cells = trimmed.split(separator: "|", omittingEmptySubsequences: true)
        guard !cells.isEmpty else { return false }
        return cells.allSatisfy { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            return !value.isEmpty && value.allSatisfy { $0 == "-" || $0 == ":" } && value.contains("-")
        }
    }

    private static func parseAlignments(_ divider: String) -> [ColumnAlignment] {
        splitRow(divider, columns: nil).map { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            switch (value.hasPrefix(":"), value.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            case (false, false): return .none
            }
        }
    }

    private static func splitRow(_ line: String, columns: Int?) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        var cells = trimmed
            .components(separatedBy: "|")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        if let columns {
            while cells.count < columns { cells.append("") }
            cells = Array(cells.prefix(columns))
        }
        return cells
    }

    private static func columnIndex(forLocation location: Int, lineRange: NSRange, line: String) -> Int {
        let offset = max(0, location - lineRange.location)
        let prefix = (line as NSString).substring(to: min(offset, (line as NSString).length))
        // Cells are separated by pipes; the leading pipe doesn't open a cell.
        return max(0, prefix.filter { $0 == "|" }.count - 1)
    }

    // MARK: - Line helpers

    private static func clamp(_ range: NSRange, in source: NSString) -> NSRange {
        let location = max(0, min(range.location, source.length))
        let length = max(0, min(range.length, source.length - location))
        return NSRange(location: location, length: length)
    }

    static func insertBlock(_ text: String, range: NSRange, block: String) -> MarkdownEdit {
        let source = text as NSString
        let safeRange = clamp(range, in: source)
        let lineRange = source.lineRange(for: safeRange)

        let insertLocation = lineRange.upperBound
        let preceding = source.substring(to: insertLocation)
        let following = source.substring(from: insertLocation)

        // A table, rule, or fence only starts a new Markdown block if a blank
        // line precedes it — without this the table was glued onto the end of
        // the previous paragraph and stopped being a table at all.
        let prefix: String
        if preceding.isEmpty || preceding.hasSuffix("\n\n") {
            prefix = ""
        } else if preceding.hasSuffix("\n") {
            prefix = "\n"
        } else {
            prefix = "\n\n"
        }

        let suffix = following.isEmpty || following.hasPrefix("\n") ? "\n" : "\n\n"
        let replacement = prefix + block + suffix

        let updated = source.replacingCharacters(
            in: NSRange(location: insertLocation, length: 0),
            with: replacement
        )
        return MarkdownEdit(
            text: updated,
            selectedRange: NSRange(
                location: insertLocation + (prefix as NSString).length,
                length: (block as NSString).length
            )
        )
    }

    private static func touchedLines(_ text: String, range: NSRange) -> [String] {
        let source = text as NSString
        let lineRange = source.lineRange(for: clamp(range, in: source))
        var block = source.substring(with: lineRange)
        if block.hasSuffix("\n") { block.removeLast() }
        return block.components(separatedBy: "\n")
    }

    private static func transformLines(
        _ text: String,
        range: NSRange,
        _ transform: (String) -> String
    ) -> MarkdownEdit {
        let source = text as NSString
        let lineRange = source.lineRange(for: clamp(range, in: source))
        var block = source.substring(with: lineRange)

        var trailingNewline = ""
        if block.hasSuffix("\n") {
            block.removeLast()
            trailingNewline = "\n"
        }

        let transformed = block
            .components(separatedBy: "\n")
            .map(transform)
            .joined(separator: "\n")

        let updated = source.replacingCharacters(in: lineRange, with: transformed + trailingNewline)
        return MarkdownEdit(
            text: updated,
            selectedRange: NSRange(location: lineRange.location, length: (transformed as NSString).length)
        )
    }

    private static func stripHeading(from line: String) -> String {
        guard line.hasPrefix("#") else { return line }
        let withoutHashes = line.drop(while: { $0 == "#" })
        return String(withoutHashes.drop(while: { $0 == " " }))
    }

    private static func removePrefix(_ prefix: String, from line: String) -> String {
        let trimmedPrefix = prefix.trimmingCharacters(in: .whitespaces)
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var body = String(line.dropFirst(leading.count))

        if body.hasPrefix(prefix) {
            body.removeFirst(prefix.count)
        } else if body.hasPrefix(trimmedPrefix) {
            body.removeFirst(trimmedPrefix.count)
            if body.hasPrefix(" ") { body.removeFirst() }
        }
        return leading + body
    }

    private static func removeAnyListPrefix(from line: String) -> String {
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        var body = String(line.dropFirst(leading.count))

        for marker in ["- [ ] ", "- [x] ", "- ", "* ", "+ ", "> "] where body.hasPrefix(marker) {
            body.removeFirst(marker.count)
            return leading + body
        }
        return leading + removeOrderedPrefix(from: body)
    }

    private static func isOrderedItem(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let digits = trimmed.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return false }
        let rest = trimmed.dropFirst(digits.count)
        return rest.hasPrefix(". ") || rest.hasPrefix(") ")
    }

    private static func removeOrderedPrefix(from line: String) -> String {
        let leading = String(line.prefix(while: { $0 == " " || $0 == "\t" }))
        let body = String(line.dropFirst(leading.count))
        let digits = body.prefix(while: { $0.isNumber })
        guard !digits.isEmpty else { return line }

        let rest = body.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return line }
        return leading + String(rest.dropFirst(2))
    }
}
