import Foundation

/// [RichDocument] → Markdown.
///
/// The inverse of [MarkdownDocumentParser]. Together they have to satisfy one
/// property above all others: parsing what this writes must reproduce the same
/// document. If that ever fails, editing a file silently corrupts it.
enum MarkdownDocumentSerializer {

    static func serialize(_ document: RichDocument) -> String {
        let body = document.blocks
            .map(serialize(_:))
            .filter { !$0.isEmpty || true }
            .joined(separator: "\n\n")

        return body.isEmpty ? "" : body + "\n"
    }

    static func serialize(_ block: RichBlock) -> String {
        switch block.content {
        case .paragraph(let text):
            return serialize(text)

        case .heading(let level, let content):
            let hashes = String(repeating: "#", count: min(max(level, 1), 6))
            return "\(hashes) \(serialize(content))"

        case .list(let style, let items):
            return serialize(style: style, items: items)

        case .quote(let blocks):
            let inner = blocks.map(serialize(_:)).joined(separator: "\n\n")
            return inner
                .components(separatedBy: "\n")
                .map { $0.isEmpty ? ">" : "> \($0)" }
                .joined(separator: "\n")

        case .code(let language, let text):
            // A fence has to be longer than any run of backticks inside it.
            let longestRun = longestBacktickRun(in: text)
            let fence = String(repeating: "`", count: max(3, longestRun + 1))
            return "\(fence)\(language ?? "")\n\(text)\n\(fence)"

        case .table(let table):
            return serialize(table)

        case .divider:
            return "---"

        case .raw(let text):
            return text
        }
    }

    // MARK: - Inline

    static func serialize(_ text: InlineText) -> String {
        text.normalized().runs.map(serialize(_:)).joined()
    }

    private static func serialize(_ run: InlineRun) -> String {
        guard !run.text.isEmpty else { return "" }

        // Code spans take no other formatting inside them.
        if run.style.contains(.code) {
            let longestRun = longestBacktickRun(in: run.text)
            let fence = String(repeating: "`", count: max(1, longestRun + 1))
            let padding = run.text.hasPrefix("`") || run.text.hasSuffix("`") ? " " : ""
            let code = "\(fence)\(padding)\(run.text)\(padding)\(fence)"
            return wrapLink(code, destination: run.link)
        }

        var body = escape(run.text)

        if run.style.contains(.strikethrough) { body = "~~\(body)~~" }
        // Bold before italic gives ***text*** rather than *​**text**​*.
        if run.style.contains(.bold) { body = "**\(body)**" }
        if run.style.contains(.italic) { body = "*\(body)*" }
        if run.style.contains(.highlight) { body = "==\(body)==" }

        return wrapLink(body, destination: run.link)
    }

    private static func wrapLink(_ body: String, destination: String?) -> String {
        guard let destination else { return body }
        return "[\(body)](\(destination))"
    }

    /// Escapes only what would otherwise be re-read as syntax. Over-escaping
    /// makes the saved file unpleasant to read outside the app.
    private static func escape(_ text: String) -> String {
        var result = ""
        result.reserveCapacity(text.count)

        var previous: Character?
        for character in text {
            switch character {
            case "*", "_", "`", "~", "[", "]", "\\":
                result.append("\\")
                result.append(character)
            case "=" where previous == "=":
                // Only a *pair* of equals signs is highlight syntax, so only
                // the second of a pair needs escaping — "a = b" stays clean.
                result.append("\\")
                result.append(character)
            default:
                result.append(character)
            }
            previous = character
        }
        return result
    }

    // MARK: - Lists

    private static func serialize(style: ListStyle, items: [ListItem]) -> String {
        var lines: [String] = []
        var number: Int

        if case .ordered(let start) = style {
            number = start
        } else {
            number = 1
        }

        for item in items {
            let indent = String(repeating: "  ", count: max(0, item.indent))
            let body = serialize(item.content)

            let marker: String
            switch style {
            case .bulleted:
                marker = "- "
            case .ordered:
                marker = "\(number). "
                number += 1
            }

            if let checkbox = item.checkbox {
                lines.append("\(indent)\(marker)[\(checkbox ? "x" : " ")] \(body)")
            } else {
                lines.append("\(indent)\(marker)\(body)")
            }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Tables

    private static func serialize(_ table: TableBlock) -> String {
        var normalized = table
        normalized.normalize()

        // Merged cells, vertical alignment, and per-cell alignment have no
        // Markdown spelling. Writing such a table as pipes would quietly throw
        // those away, so it goes out as HTML — which every Markdown renderer
        // passes through — while ordinary tables stay ordinary.
        if normalized.needsHTML {
            return serializeAsHTML(normalized)
        }

        func row(_ row: TableRow) -> String {
            let cells = row.cells.map { cell -> String in
                let body = serialize(cell.content)
                    // A literal pipe would end the cell.
                    .replacingOccurrences(of: "|", with: "\\|")
                return body.isEmpty ? " " : body
            }
            return "| " + cells.joined(separator: " | ") + " |"
        }

        let divider = "| " + normalized.alignments.map { alignment -> String in
            switch alignment {
            case .none: return "---"
            case .left: return ":---"
            case .center: return ":---:"
            case .right: return "---:"
            }
        }.joined(separator: " | ") + " |"

        return ([row(normalized.header), divider] + normalized.rows.map(row)).joined(separator: "\n")
    }

    /// Writes a table that Markdown syntax cannot hold.
    ///
    /// Inline content still goes through the Markdown serialiser and is emitted
    /// with `markdown="1"`, so bold and links inside cells keep working in
    /// renderers that honour it and read acceptably in those that don't.
    private static func serializeAsHTML(_ table: TableBlock) -> String {
        func cellHTML(_ cell: TableCell, tag: String, columnAlignment: TableColumnAlignment) -> String? {
            guard !cell.isCovered else { return nil }

            var attributes: [String] = []
            let horizontal = cell.horizontalAlignment ?? columnAlignment
            if horizontal != .none {
                attributes.append("align=\"\(horizontal.rawValue)\"")
            }
            if let vertical = cell.verticalAlignment {
                attributes.append("valign=\"\(vertical.rawValue)\"")
            }
            if cell.columnSpan > 1 { attributes.append("colspan=\"\(cell.columnSpan)\"") }
            if cell.rowSpan > 1 { attributes.append("rowspan=\"\(cell.rowSpan)\"") }

            let opening = attributes.isEmpty ? tag : "\(tag) \(attributes.joined(separator: " "))"
            let body = serialize(cell.content)
            return "<\(tag == "th" ? opening : opening)>\(body)</\(tag)>"
        }

        func rowHTML(_ row: TableRow, tag: String) -> String {
            let cells = row.cells.enumerated().compactMap { index, cell in
                cellHTML(
                    cell,
                    tag: tag,
                    columnAlignment: table.alignments.indices.contains(index)
                        ? table.alignments[index]
                        : .none
                )
            }
            return "<tr>\n\(cells.map { "  \($0)" }.joined(separator: "\n"))\n</tr>"
        }

        var lines: [String] = ["<table markdown=\"1\">", "<thead>", rowHTML(table.header, tag: "th"), "</thead>"]
        if !table.rows.isEmpty {
            lines.append("<tbody>")
            lines.append(contentsOf: table.rows.map { rowHTML($0, tag: "td") })
            lines.append("</tbody>")
        }
        lines.append("</table>")
        return lines.joined(separator: "\n")
    }

    private static func longestBacktickRun(in text: String) -> Int {
        var longest = 0
        var current = 0
        for character in text {
            if character == "`" {
                current += 1
                longest = max(longest, current)
            } else {
                current = 0
            }
        }
        return longest
    }
}
