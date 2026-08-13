import AppKit
import SwiftUI

/// Where the caret is inside a table, in terms the formatting panel can show.
///
/// Deliberately independent of *which* surface produced it: the canvas reports
/// it from the focused cell of a live grid, and Source mode still derives it
/// from Markdown text. The panel doesn't need to know which.
struct TableEditingContext: Equatable {
    var caretRow: Int
    var caretColumn: Int
    var rowCount: Int
    var columnCount: Int
    var alignments: [TableColumnAlignment]
    /// The focused cell's own overrides, when it has any. Only a live grid
    /// knows these; Source mode leaves them nil.
    var cellAlignment: TableColumnAlignment?
    var cellVerticalAlignment: TableVerticalAlignment?
    /// Whether the focused cell is a merge that can be split again.
    var isMerged: Bool
    /// Whether this surface can merge at all — Source mode edits Markdown
    /// text, which has no way to say "merged".
    var supportsCellFeatures: Bool

    init(
        caretRow: Int,
        caretColumn: Int,
        rowCount: Int,
        columnCount: Int,
        alignments: [TableColumnAlignment],
        cellAlignment: TableColumnAlignment? = nil,
        cellVerticalAlignment: TableVerticalAlignment? = nil,
        isMerged: Bool = false,
        supportsCellFeatures: Bool = false
    ) {
        self.caretRow = caretRow
        self.caretColumn = caretColumn
        self.rowCount = rowCount
        self.columnCount = columnCount
        self.alignments = alignments
        self.cellAlignment = cellAlignment
        self.cellVerticalAlignment = cellVerticalAlignment
        self.isMerged = isMerged
        self.supportsCellFeatures = supportsCellFeatures
    }

    /// Row 0 is the header, which cannot be deleted.
    var canDeleteRow: Bool { caretRow > 0 && rowCount > 1 }
    var canDeleteColumn: Bool { columnCount > 1 }

    var canMergeRight: Bool { supportsCellFeatures && caretColumn < columnCount - 1 }
    var canMergeDown: Bool { supportsCellFeatures && caretRow < rowCount - 1 }

    var currentAlignment: TableColumnAlignment {
        alignments.indices.contains(caretColumn) ? alignments[caretColumn] : .none
    }
}

extension MarkdownFormatter.TableContext {
    /// Source mode still edits Markdown text, so it keeps its own finder and
    /// converts into the shared shape here.
    var editingContext: TableEditingContext {
        TableEditingContext(
            caretRow: caretRow,
            caretColumn: caretColumn,
            rowCount: rows.count,
            columnCount: columnCount,
            // The source-mode formatter has its own alignment enum; the two
            // describe the same four states.
            alignments: alignments.map(TableColumnAlignment.init(formatter:))
        )
    }
}

extension TableColumnAlignment {
    init(formatter: MarkdownFormatter.ColumnAlignment) {
        switch formatter {
        case .left: self = .left
        case .center: self = .center
        case .right: self = .right
        case .none: self = .none
        }
    }

    var formatterAlignment: MarkdownFormatter.ColumnAlignment {
        switch self {
        case .left: return .left
        case .center: return .center
        case .right: return .right
        case .none: return .none
        }
    }
}

enum TableGridCommand: Equatable {
    case addRow
    case addColumn
    case deleteRow
    case deleteColumn
    case setAlignment(TableColumnAlignment)
    case setCellAlignment(TableColumnAlignment?)
    case setCellVerticalAlignment(TableVerticalAlignment?)
    case mergeRight
    case mergeDown
    case unmerge
}

/// Connects the formatting panel to whichever table the user is actually in.
///
/// A table lives inside a text attachment, so the caret is never "inside" one
/// as far as anything reading Markdown source is concerned — which is why the
/// panel's table controls went dead when tables became objects. The focused
/// grid reports itself here, and commands travel back down the same path.
@MainActor
final class TableSelectionBridge: ObservableObject {
    @Published private(set) var context: TableEditingContext?

    private weak var grid: DocumentTableView?

    func focus(_ grid: DocumentTableView, context: TableEditingContext) {
        self.grid = grid
        if self.context != context {
            self.context = context
        }
    }

    /// Called when a grid loses focus. Ignored if a *different* grid has since
    /// taken it, so tabbing between two tables doesn't blank the panel.
    func release(_ grid: DocumentTableView) {
        guard self.grid === grid else { return }
        self.grid = nil
        context = nil
    }

    func clear() {
        grid = nil
        context = nil
    }

    @discardableResult
    func apply(_ command: TableGridCommand) -> Bool {
        guard let grid, let context else { return false }

        switch command {
        case .addRow:
            grid.insertRow(at: context.caretRow)
        case .addColumn:
            grid.insertColumn(at: context.caretColumn + 1)
        case .deleteRow:
            guard context.canDeleteRow else { return false }
            grid.deleteRow(at: context.caretRow)
        case .deleteColumn:
            guard context.canDeleteColumn else { return false }
            grid.deleteColumn(at: context.caretColumn)
        case .setAlignment(let alignment):
            grid.setAlignment(alignment, forColumn: context.caretColumn)
        case .setCellAlignment(let alignment):
            grid.setCellAlignment(alignment)
        case .setCellVerticalAlignment(let alignment):
            grid.setCellVerticalAlignment(alignment)
        case .mergeRight:
            guard grid.mergeFocusedCell(rowsToAdd: 0, columnsToAdd: 1) else { return false }
        case .mergeDown:
            guard grid.mergeFocusedCell(rowsToAdd: 1, columnsToAdd: 0) else { return false }
        case .unmerge:
            guard grid.unmergeFocusedCell() else { return false }
        }

        // The grid rebuilt its cells, so re-publish what it now looks like.
        self.context = grid.currentEditingContext(row: context.caretRow, column: context.caretColumn)
        return true
    }
}
