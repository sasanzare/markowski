import Foundation

/// Short, stable names for the blocks of a document, for the assistant to
/// address them by.
///
/// A `UUID` is the wrong thing to ask a language model to copy — long, easy to
/// corrupt, and a single wrong character means the operation lands nowhere.
/// `b1`, `b2`, `b3` are hard to get wrong, and the mapping back is exact.
struct AIBlockHandles {
    private let byHandle: [String: UUID]
    private let byID: [UUID: String]

    init(document: RichDocument) {
        var byHandle: [String: UUID] = [:]
        var byID: [UUID: String] = [:]

        for (index, block) in document.blocks.enumerated() {
            let handle = "b\(index + 1)"
            byHandle[handle] = block.id
            byID[block.id] = handle
        }
        self.byHandle = byHandle
        self.byID = byID
    }

    func id(for handle: String) -> UUID? {
        byHandle[handle.trimmingCharacters(in: .whitespaces).lowercased()]
    }

    func handle(for id: UUID) -> String? { byID[id] }

    var count: Int { byHandle.count }
}

enum AIOperationError: LocalizedError, Equatable {
    case unknownHandle(String)
    case unknownOperation(String)
    case missingField(operation: String, field: String)
    case empty

    var errorDescription: String? {
        switch self {
        case .unknownHandle(let handle):
            return "The assistant referred to “\(handle)”, which isn’t a block in this document."
        case .unknownOperation(let name):
            return "The assistant asked for “\(name)”, which isn’t something this document can do."
        case .missingField(let operation, let field):
            return "The assistant’s “\(operation)” was missing “\(field)”."
        case .empty:
            return "The assistant proposed no changes."
        }
    }
}

/// Decodes the assistant's JSON into validated [DocumentOperation]s.
///
/// This is the whole point of Stage 4: "make this paragraph shorter" arrives as
/// one operation against one block, not a regenerated copy of the file. Nothing
/// outside the addressed blocks can change, because nothing else is described.
enum AIDocumentOperations {

    /// Renders the document for the prompt with a handle above each block, so
    /// the model can see exactly what it is allowed to address.
    static func promptListing(for document: RichDocument, handles: AIBlockHandles) -> String {
        guard !document.blocks.isEmpty else {
            return "[EMPTY DOCUMENT — create the first content with insertBlock and omit after]"
        }

        return document.blocks.enumerated().map { index, block in
            let handle = handles.handle(for: block.id) ?? "b\(index + 1)"
            let body = MarkdownDocumentSerializer.serialize(block)
            return "[\(handle)]\n\(body)"
        }.joined(separator: "\n\n")
    }

    static func decode(
        _ raw: [[String: Any]],
        handles: AIBlockHandles
    ) throws -> [DocumentOperation] {
        let operations = try raw.flatMap { try decode($0, handles: handles) }
        guard !operations.isEmpty else { throw AIOperationError.empty }
        return operations
    }

    static func decode(
        _ raw: [String: Any],
        handles: AIBlockHandles
    ) throws -> [DocumentOperation] {
        guard let name = (raw["op"] as? String ?? raw["operation"] as? String)?
            .trimmingCharacters(in: .whitespaces) else {
            throw AIOperationError.missingField(operation: "operation", field: "op")
        }

        func blockID(_ field: String = "block") throws -> UUID {
            guard let handle = raw[field] as? String else {
                throw AIOperationError.missingField(operation: name, field: field)
            }
            guard let id = handles.id(for: handle) else {
                throw AIOperationError.unknownHandle(handle)
            }
            return id
        }

        func markdown(_ field: String = "markdown") throws -> String {
            guard let value = raw[field] as? String else {
                throw AIOperationError.missingField(operation: name, field: field)
            }
            return value
        }

        func integer(_ field: String) throws -> Int {
            if let value = raw[field] as? Int { return value }
            if let value = raw[field] as? String, let parsed = Int(value) { return parsed }
            throw AIOperationError.missingField(operation: name, field: field)
        }

        switch name.lowercased() {
        case "replaceblock", "replace", "rewriteblock":
            let blocks = MarkdownDocumentParser.parse(try markdown()).blocks
            return [.replaceBlock(try blockID(), with: blocks)]

        case "insertblock", "insert", "insertblocks", "createdocument", "setdocument":
            let blocks = MarkdownDocumentParser.parse(try markdown()).blocks
            guard !blocks.isEmpty else {
                throw AIOperationError.missingField(operation: name, field: "markdown")
            }
            if ["createdocument", "setdocument"].contains(name.lowercased()), handles.count > 0 {
                throw AIOperationError.unknownOperation(name)
            }
            // "after" is optional: absent means the top of the document.
            let after = (raw["after"] as? String).flatMap { handles.id(for: $0) }
            if raw["after"] is String, after == nil {
                throw AIOperationError.unknownHandle(raw["after"] as? String ?? "")
            }
            // One model operation may contain a complete multi-block Markdown
            // document. Expand it without dropping blocks and chain each
            // insertion after the previous new block so source order survives.
            var previous = after
            return blocks.map { block in
                defer { previous = block.id }
                return .insertBlock(block, after: previous)
            }

        case "deleteblock", "delete":
            return [.deleteBlock(try blockID())]

        case "moveblock", "move":
            return [.moveBlock(try blockID(), toIndex: try integer("toIndex"))]

        case "setheadinglevel", "setheading":
            return [.setHeadingLevel(block: try blockID(), level: try integer("level"))]

        case "converttoparagraph":
            return [.convertToParagraph(block: try blockID())]

        case "converttolist":
            let styleName = (raw["style"] as? String ?? "bulleted").lowercased()
            let style: ListStyle = styleName.hasPrefix("order") || styleName.hasPrefix("number")
                ? .ordered(start: 1)
                : .bulleted
            return [.convertToList(block: try blockID(), style: style)]

        case "setcell":
            let content = MarkdownDocumentParser.parseInline(try markdown())
            return [.setCell(
                block: try blockID(),
                row: try integer("row"),
                column: try integer("column"),
                content: content
            )]

        case "inserttablerow", "addrow":
            return [.insertTableRow(block: try blockID(), at: try integer("at"))]

        case "deletetablerow", "deleterow":
            return [.deleteTableRow(block: try blockID(), at: try integer("at"))]

        case "inserttablecolumn", "addcolumn":
            return [.insertTableColumn(block: try blockID(), at: try integer("at"))]

        case "deletetablecolumn", "deletecolumn":
            return [.deleteTableColumn(block: try blockID(), at: try integer("at"))]

        case "setcolumnalignment", "setalignment":
            let value = (raw["alignment"] as? String ?? "none").lowercased()
            let alignment: TableColumnAlignment
            switch value {
            case "left": alignment = .left
            case "center", "centre": alignment = .center
            case "right": alignment = .right
            default: alignment = .none
            }
            return [.setColumnAlignment(
                block: try blockID(),
                column: try integer("column"),
                alignment: alignment
            )]

        default:
            throw AIOperationError.unknownOperation(name)
        }
    }

    /// A short, human sentence per operation, for the review UI. The point of a
    /// scoped edit is that the user can see *what* is being changed before
    /// looking at a single character of diff.
    static func describe(
        _ operation: DocumentOperation,
        in document: RichDocument,
        handles: AIBlockHandles
    ) -> String {
        func label(_ id: UUID) -> String {
            guard let index = document.index(of: id) else { return "a block" }
            let block = document.blocks[index]
            let kind: String
            switch block.content {
            case .heading(let level, _): kind = "heading \(level)"
            case .paragraph: kind = "paragraph"
            case .list: kind = "list"
            case .table: kind = "table"
            case .code: kind = "code block"
            case .quote: kind = "quote"
            case .divider: kind = "divider"
            case .raw: kind = "raw block"
            }

            let preview = block.plainText
                .replacingOccurrences(of: "\n", with: " ")
                .trimmingCharacters(in: .whitespaces)
            guard !preview.isEmpty else { return kind }
            return "\(kind) “\(preview.prefix(38))\(preview.count > 38 ? "…" : "")”"
        }

        switch operation {
        case .replaceBlock(let id, _): return "Rewrite \(label(id))"
        case .replaceInline(let id, _): return "Rewrite \(label(id))"
        case .setStyle(let id, _, _, _): return "Restyle text in \(label(id))"
        case .setLink(let id, _, _): return "Change a link in \(label(id))"
        case .setHeadingLevel(let id, let level):
            return level <= 0 ? "Turn \(label(id)) into body text" : "Make \(label(id)) a level \(level) heading"
        case .convertToParagraph(let id): return "Turn \(label(id)) into paragraphs"
        case .convertToList(let id, _): return "Turn \(label(id)) into a list"
        case .setCheckbox(let id, _, let checked):
            return "\(checked == true ? "Check" : "Uncheck") an item in \(label(id))"
        case .insertBlock(_, let after):
            guard let after else { return "Insert a block at the top" }
            return "Insert a block after \(label(after))"
        case .deleteBlock(let id): return "Delete \(label(id))"
        case .moveBlock(let id, let index): return "Move \(label(id)) to position \(index + 1)"
        case .setCell(let id, let row, let column, _):
            return "Set row \(row + 1), column \(column + 1) of \(label(id))"
        case .insertTableRow(let id, _): return "Add a row to \(label(id))"
        case .deleteTableRow(let id, _): return "Delete a row from \(label(id))"
        case .insertTableColumn(let id, _): return "Add a column to \(label(id))"
        case .deleteTableColumn(let id, _): return "Delete a column from \(label(id))"
        case .setColumnAlignment(let id, let column, let alignment):
            return "Align column \(column + 1) of \(label(id)) \(alignment.rawValue)"
        }
    }
}
