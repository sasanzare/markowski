import Foundation

/// Markdown → [RichDocument].
///
/// This exists so Markdown can be an import format rather than the thing being
/// edited. It covers the block and inline syntax the editor can represent;
/// anything else is preserved verbatim as a `.raw` block so opening and saving
/// a file never destroys what it didn't understand.
enum MarkdownDocumentParser {

    static func parse(_ markdown: String) -> RichDocument {
        var lines = markdown.components(separatedBy: "\n")
        // A trailing newline produces a final empty line that is layout, not
        // content.
        if lines.last?.isEmpty == true { lines.removeLast() }

        var blocks: [RichBlock] = []
        var index = 0

        while index < lines.count {
            let line = lines[index]

            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                index += 1
                continue
            }

            if let block = parseThematicBreak(line) {
                blocks.append(block)
                index += 1
                continue
            }

            if let block = parseHeading(line) {
                blocks.append(block)
                index += 1
                continue
            }

            if let (block, consumed) = parseFencedCode(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            if let (block, consumed) = parseTable(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            if let (block, consumed) = parseList(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            if let (block, consumed) = parseQuote(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            // Before the generic HTML passthrough: a table we wrote because it
            // needed more than Markdown offers has to come back as a real
            // table, not as opaque markup the editor can't touch.
            if let (block, consumed) = parseHTMLTable(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            if let (block, consumed) = parseHTMLBlock(lines, from: index) {
                blocks.append(block)
                index += consumed
                continue
            }

            let (block, consumed) = parseParagraph(lines, from: index)
            blocks.append(block)
            index += consumed
        }

        return RichDocument(blocks: blocks).normalized()
    }

    // MARK: - Block parsers

    private static func parseThematicBreak(_ line: String) -> RichBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 3 else { return nil }

        for marker: Character in ["-", "*", "_"] {
            if trimmed.allSatisfy({ $0 == marker }) {
                return RichBlock(content: .divider)
            }
        }
        return nil
    }

    private static func parseHeading(_ line: String) -> RichBlock? {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let hashes = trimmed.prefix(while: { $0 == "#" }).count
        guard hashes >= 1, hashes <= 6 else { return nil }

        let rest = trimmed.dropFirst(hashes)
        // "#hashtag" is not a heading; ATX requires a space (or nothing).
        guard rest.isEmpty || rest.hasPrefix(" ") else { return nil }

        var text = String(rest).trimmingCharacters(in: .whitespaces)
        // Optional closing sequence: "## Title ##"
        while text.hasSuffix("#") { text.removeLast() }
        text = text.trimmingCharacters(in: .whitespaces)

        return RichBlock(content: .heading(level: hashes, content: parseInline(text)))
    }

    private static func parseFencedCode(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        let opening = lines[start].trimmingCharacters(in: .whitespaces)
        guard let fenceCharacter = opening.first, fenceCharacter == "`" || fenceCharacter == "~" else {
            return nil
        }

        // The fence is the *whole* run, not the first three. A code block whose
        // content contains ``` is written with a longer fence, and reading only
        // three back would end the block on its own content.
        let fenceLength = opening.prefix(while: { $0 == fenceCharacter }).count
        guard fenceLength >= 3 else { return nil }

        let language = String(opening.dropFirst(fenceLength)).trimmingCharacters(in: .whitespaces)
        // An info string can't contain a backtick.
        guard !(fenceCharacter == "`" && language.contains("`")) else { return nil }

        var body: [String] = []
        var index = start + 1

        while index < lines.count {
            let candidate = lines[index].trimmingCharacters(in: .whitespaces)
            let closingLength = candidate.prefix(while: { $0 == fenceCharacter }).count
            // A closing fence is at least as long as the opening one, and holds
            // nothing else.
            if closingLength >= fenceLength, candidate.count == closingLength {
                index += 1
                break
            }
            body.append(lines[index])
            index += 1
        }

        // An unterminated fence still becomes a code block — that is what the
        // author was typing.
        return (
            RichBlock(content: .code(
                language: language.isEmpty ? nil : language,
                text: body.joined(separator: "\n")
            )),
            index - start
        )
    }

    private static func parseTable(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        guard start + 1 < lines.count,
              isTableRow(lines[start]),
              isDividerRow(lines[start + 1]) else {
            return nil
        }

        let alignments = parseAlignments(lines[start + 1])
        let header = TableRow(cells: splitCells(lines[start], width: alignments.count).map {
            TableCell(content: parseInline($0))
        })

        var rows: [TableRow] = []
        var index = start + 2
        while index < lines.count, isTableRow(lines[index]) {
            rows.append(TableRow(cells: splitCells(lines[index], width: alignments.count).map {
                TableCell(content: parseInline($0))
            }))
            index += 1
        }

        var table = TableBlock(header: header, rows: rows, alignments: alignments)
        table.normalize()
        return (RichBlock(content: .table(table)), index - start)
    }

    /// Reads an HTML `<table>` back into a real `TableBlock`.
    ///
    /// This is the other half of writing merged and per-cell-aligned tables as
    /// HTML: without it they would reopen as opaque `.raw` markup and stop
    /// being editable the moment they were saved.
    private static func parseHTMLTable(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        guard lines[start].trimmingCharacters(in: .whitespaces).lowercased().hasPrefix("<table") else {
            return nil
        }

        // Gather to the closing tag. A table that never closes is not one.
        var index = start
        var body: [String] = []
        var found = false
        while index < lines.count {
            body.append(lines[index])
            if lines[index].lowercased().contains("</table>") {
                found = true
                index += 1
                break
            }
            index += 1
        }
        guard found else { return nil }

        let html = body.joined(separator: "\n")
        guard let table = tableBlock(fromHTML: html) else { return nil }
        return (RichBlock(content: .table(table)), index - start)
    }

    /// One `<td>`/`<th>` as read off the page.
    private struct ParsedHTMLCell {
        var content: InlineText
        var horizontalAlignment: TableColumnAlignment?
        var verticalAlignment: TableVerticalAlignment?
        var columnSpan: Int
        var rowSpan: Int
    }

    static func tableBlock(fromHTML html: String) -> TableBlock? {
        let rows = matches(of: "<tr[^>]*>(.*?)</tr>", in: html).map { rowHTML -> [ParsedHTMLCell] in
            matches(of: "<(t[hd])([^>]*)>(.*?)</t[hd]>", in: rowHTML, groups: 3).map { groups in
                ParsedHTMLCell(
                    content: parseInline(decodeEntities(groups[2]).trimmingCharacters(in: .whitespacesAndNewlines)),
                    horizontalAlignment: attribute("align", in: groups[1])
                        .flatMap { TableColumnAlignment(rawValue: $0.lowercased()) },
                    verticalAlignment: attribute("valign", in: groups[1])
                        .flatMap { TableVerticalAlignment(rawValue: $0.lowercased()) },
                    columnSpan: attribute("colspan", in: groups[1]).flatMap(Int.init) ?? 1,
                    rowSpan: attribute("rowspan", in: groups[1]).flatMap(Int.init) ?? 1
                )
            }
        }
        guard let headerCells = rows.first, !headerCells.isEmpty else { return nil }

        // Lay the cells into a rectangle, leaving room for the ones that span.
        let width = headerCells.reduce(0) { $0 + max(1, $1.columnSpan) }
        guard width > 0 else { return nil }

        var grid: [[TableCell]] = Array(
            repeating: Array(repeating: TableCell(isCovered: true), count: width),
            count: rows.count
        )
        var taken = Array(repeating: Array(repeating: false, count: width), count: rows.count)

        for (rowIndex, row) in rows.enumerated() {
            var column = 0
            for parsed in row {
                while column < width, taken[rowIndex][column] { column += 1 }
                guard column < width else { break }

                let columnSpan = max(1, min(parsed.columnSpan, width - column))
                let rowSpan = max(1, min(parsed.rowSpan, rows.count - rowIndex))
                grid[rowIndex][column] = TableCell(
                    content: parsed.content,
                    horizontalAlignment: parsed.horizontalAlignment,
                    verticalAlignment: parsed.verticalAlignment,
                    columnSpan: columnSpan,
                    rowSpan: rowSpan
                )
                for r in rowIndex..<(rowIndex + rowSpan) {
                    for c in column..<(column + columnSpan) {
                        taken[r][c] = true
                    }
                }
                column += columnSpan
            }
        }

        // A whole column carrying one alignment is a column alignment; anything
        // else stays on the cells that asked for it.
        var alignments: [TableColumnAlignment] = []
        for column in 0..<width {
            let stated = grid.compactMap { $0[column].isCovered ? nil : $0[column].horizontalAlignment }
            let uniform = Set(stated)
            alignments.append(uniform.count == 1 && stated.count == grid.count ? stated[0] : .none)
        }
        for column in 0..<width where alignments[column] != .none {
            for row in grid.indices { grid[row][column].horizontalAlignment = nil }
        }

        var table = TableBlock(
            header: TableRow(cells: grid[0]),
            rows: grid.dropFirst().map { TableRow(cells: $0) },
            alignments: alignments
        )
        table.normalize()
        return table
    }

    private static func attribute(_ name: String, in attributes: String) -> String? {
        matches(of: "\(name)\\s*=\\s*[\"']([^\"']*)[\"']", in: attributes).first
    }

    /// Capture group 1 of every match, or all `groups` captures per match.
    private static func matches(of pattern: String, in text: String) -> [String] {
        matches(of: pattern, in: text, groups: 1).map { $0[0] }
    }

    private static func matches(of pattern: String, in text: String, groups: Int) -> [[String]] {
        guard let expression = try? NSRegularExpression(
            pattern: pattern,
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else {
            return []
        }
        let source = text as NSString
        return expression
            .matches(in: text, options: [], range: NSRange(location: 0, length: source.length))
            .map { match in
                (1...groups).map { index in
                    let range = match.range(at: index)
                    return range.location == NSNotFound ? "" : source.substring(with: range)
                }
            }
    }

    private static func decodeEntities(_ text: String) -> String {
        var result = text
        for (entity, character) in [
            ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&nbsp;", " "), ("&amp;", "&")
        ] {
            result = result.replacingOccurrences(of: entity, with: character)
        }
        return result
    }

    private static func parseList(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        guard let first = listItem(from: lines[start]) else { return nil }

        var items: [ListItem] = [first.item]
        var style = first.style
        var index = start + 1

        while index < lines.count {
            let line = lines[index]
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                // A blank line ends the list unless another item follows.
                if index + 1 < lines.count, listItem(from: lines[index + 1]) != nil {
                    index += 1
                    continue
                }
                break
            }
            guard let next = listItem(from: line), sameFamily(style, next.style) else { break }

            items.append(next.item)
            index += 1
        }

        return (RichBlock(content: .list(style: style, items: items)), index - start)
    }

    private static func parseQuote(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        guard lines[start].trimmingCharacters(in: .whitespaces).hasPrefix(">") else { return nil }

        var inner: [String] = []
        var index = start
        while index < lines.count {
            let trimmed = lines[index].trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix(">") else { break }
            var content = String(trimmed.dropFirst())
            if content.hasPrefix(" ") { content.removeFirst() }
            inner.append(content)
            index += 1
        }

        // A quote holds blocks, so it is parsed with the same machinery.
        let nested = parse(inner.joined(separator: "\n"))
        return (RichBlock(content: .quote(blocks: nested.blocks)), index - start)
    }

    /// Raw HTML is kept verbatim. The `<div dir="rtl">` wrappers the formatting
    /// panel writes come through here.
    private static func parseHTMLBlock(_ lines: [String], from start: Int) -> (RichBlock, Int)? {
        let trimmed = lines[start].trimmingCharacters(in: .whitespaces)
        guard trimmed.hasPrefix("<"), trimmed.count > 1 else { return nil }

        let second = trimmed[trimmed.index(after: trimmed.startIndex)]
        guard second.isLetter || second == "/" || second == "!" else { return nil }

        var body: [String] = []
        var index = start
        while index < lines.count, !lines[index].trimmingCharacters(in: .whitespaces).isEmpty {
            body.append(lines[index])
            index += 1
        }
        return (RichBlock(content: .raw(body.joined(separator: "\n"))), index - start)
    }

    private static func parseParagraph(_ lines: [String], from start: Int) -> (RichBlock, Int) {
        var body: [String] = []
        var index = start

        while index < lines.count {
            let line = lines[index]
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { break }
            // Any block-level construct interrupts a paragraph.
            if index > start,
               parseHeading(line) != nil
                || parseThematicBreak(line) != nil
                || listItem(from: line) != nil
                || trimmed.hasPrefix(">")
                || trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~")
                || isTableRow(line) {
                break
            }
            body.append(trimmed)
            index += 1
        }

        // A soft line break inside a paragraph is rendered as a space.
        let joined = body.joined(separator: "\n")
        return (RichBlock(content: .paragraph(parseInline(joined))), max(1, index - start))
    }

    // MARK: - List helpers

    private static func listItem(from line: String) -> (item: ListItem, style: ListStyle)? {
        let leading = line.prefix(while: { $0 == " " || $0 == "\t" }).count
        let indent = min(leading / 2, 6)
        let trimmed = line.trimmingCharacters(in: .whitespaces)

        for marker in ["- ", "* ", "+ "] where trimmed.hasPrefix(marker) {
            return (item(from: String(trimmed.dropFirst(marker.count)), indent: indent), .bulleted)
        }

        let digits = trimmed.prefix(while: { $0.isNumber })
        if !digits.isEmpty, digits.count <= 9 {
            let rest = trimmed.dropFirst(digits.count)
            if rest.hasPrefix(". ") || rest.hasPrefix(") ") {
                return (
                    item(from: String(rest.dropFirst(2)), indent: indent),
                    .ordered(start: Int(digits) ?? 1)
                )
            }
        }
        return nil
    }

    /// A checkbox can follow either marker — an ordered task list is perfectly
    /// legal, and reading it only after a bullet left "[x] " sitting in the
    /// text as literal characters.
    private static func item(from body: String, indent: Int) -> ListItem {
        let lowered = body.lowercased()
        if lowered.hasPrefix("[ ] ") || lowered.hasPrefix("[x] ") {
            return ListItem(
                content: parseInline(String(body.dropFirst(4))),
                indent: indent,
                checkbox: lowered.hasPrefix("[x] ")
            )
        }
        return ListItem(content: parseInline(body), indent: indent)
    }

    private static func sameFamily(_ lhs: ListStyle, _ rhs: ListStyle) -> Bool {
        switch (lhs, rhs) {
        case (.bulleted, .bulleted), (.ordered, .ordered): return true
        default: return false
        }
    }

    // MARK: - Table helpers

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
            return !value.isEmpty && value.contains("-") && value.allSatisfy { $0 == "-" || $0 == ":" }
        }
    }

    private static func parseAlignments(_ divider: String) -> [TableColumnAlignment] {
        splitCells(divider, width: nil).map { cell in
            let value = cell.trimmingCharacters(in: .whitespaces)
            switch (value.hasPrefix(":"), value.hasSuffix(":")) {
            case (true, true): return .center
            case (true, false): return .left
            case (false, true): return .right
            case (false, false): return .none
            }
        }
    }

    private static func splitCells(_ line: String, width: Int?) -> [String] {
        var trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("|") { trimmed.removeFirst() }
        if trimmed.hasSuffix("|") { trimmed.removeLast() }

        var cells = trimmed.components(separatedBy: "|").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        if let width {
            while cells.count < width { cells.append("") }
            cells = Array(cells.prefix(width))
        }
        return cells
    }

    // MARK: - Inline parsing

    /// Turns inline Markdown into styled runs. Styles become attributes on the
    /// text; the syntax characters themselves are consumed.
    static func parseInline(_ text: String) -> InlineText {
        var runs: [InlineRun] = []
        var buffer = ""
        var style: InlineStyle = []

        let characters = Array(text)
        var index = 0

        func flush() {
            guard !buffer.isEmpty else { return }
            runs.append(InlineRun(buffer, style: style))
            buffer = ""
        }

        while index < characters.count {
            let character = characters[index]

            // Backslash escape: the next character is literal.
            if character == "\\", index + 1 < characters.count {
                buffer.append(characters[index + 1])
                index += 2
                continue
            }

            // Inline code wins over every other marker inside it.
            if character == "`" {
                if let closing = findClosing("`", in: characters, from: index + 1) {
                    flush()
                    runs.append(InlineRun(String(characters[(index + 1)..<closing]), style: style.union(.code)))
                    index = closing + 1
                    continue
                }
            }

            if character == "[", let link = parseLink(characters, from: index) {
                flush()
                var linkRuns = parseInline(link.label).runs
                if linkRuns.isEmpty { linkRuns = [InlineRun(link.label)] }
                for var run in linkRuns {
                    run.style.formUnion(style)
                    run.link = link.destination
                    runs.append(run)
                }
                index = link.end
                continue
            }

            if let marker = marker(at: index, in: characters) {
                if let closing = findClosingMarker(marker.token, in: characters, from: index + marker.token.count) {
                    flush()
                    let inner = String(characters[(index + marker.token.count)..<closing])
                    let nested = parseInline(inner)
                    for var run in nested.runs {
                        run.style.formUnion(style)
                        run.style.formUnion(marker.style)
                        runs.append(run)
                    }
                    index = closing + marker.token.count
                    continue
                }
            }

            buffer.append(character)
            index += 1
        }

        flush()
        return InlineText(runs).normalized()
    }

    private struct Marker {
        let token: String
        let style: InlineStyle
    }

    private static func marker(at index: Int, in characters: [Character]) -> Marker? {
        func matches(_ token: String) -> Bool {
            let tokenCharacters = Array(token)
            guard index + tokenCharacters.count <= characters.count else { return false }
            return Array(characters[index..<(index + tokenCharacters.count)]) == tokenCharacters
        }

        // Longest first: ** must win over *.
        if matches("***") { return Marker(token: "***", style: [.bold, .italic]) }
        if matches("~~") { return Marker(token: "~~", style: .strikethrough) }
        if matches("==") { return Marker(token: "==", style: .highlight) }
        if matches("**") { return Marker(token: "**", style: .bold) }
        if matches("__") { return Marker(token: "__", style: .bold) }
        if matches("*") { return Marker(token: "*", style: .italic) }
        if matches("_") { return Marker(token: "_", style: .italic) }
        return nil
    }

    private static func findClosingMarker(_ token: String, in characters: [Character], from start: Int) -> Int? {
        let tokenCharacters = Array(token)
        guard start < characters.count else { return nil }

        var index = start
        while index + tokenCharacters.count <= characters.count {
            if characters[index] == "\\" {
                index += 2
                continue
            }
            if Array(characters[index..<(index + tokenCharacters.count)]) == tokenCharacters {
                // An empty span isn't emphasis.
                return index > start ? index : nil
            }
            index += 1
        }
        return nil
    }

    private static func findClosing(_ token: Character, in characters: [Character], from start: Int) -> Int? {
        var index = start
        while index < characters.count {
            if characters[index] == token { return index > start ? index : nil }
            index += 1
        }
        return nil
    }

    private static func parseLink(
        _ characters: [Character],
        from start: Int
    ) -> (label: String, destination: String, end: Int)? {
        var index = start + 1
        var label = ""
        while index < characters.count, characters[index] != "]" {
            if characters[index] == "\\", index + 1 < characters.count {
                label.append(characters[index + 1])
                index += 2
                continue
            }
            label.append(characters[index])
            index += 1
        }
        guard index < characters.count, characters[index] == "]" else { return nil }

        index += 1
        guard index < characters.count, characters[index] == "(" else { return nil }

        index += 1
        var destination = ""
        var depth = 1
        while index < characters.count {
            let character = characters[index]
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { break }
            }
            destination.append(character)
            index += 1
        }
        guard index < characters.count, characters[index] == ")" else { return nil }

        return (label, destination, index + 1)
    }
}
