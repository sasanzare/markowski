import AppKit

/// A table embedded in the canvas as a real object.
///
/// Before this, a table was rows of tab-separated text: cell boundaries were a
/// fiction maintained by tab stops, a typed tab created a column, and a return
/// destroyed the row. Here the `TableBlock` *is* the thing on screen — each
/// cell is its own editable text view, and structural edits mutate the model
/// rather than rewriting characters.
///
/// The controls around the grid are real subviews rather than glyphs painted in
/// `draw(_:)`. Hand-drawn controls had to be hit-tested by hand too, and the
/// two descriptions drifted: both "+" buttons were being drawn past the bottom
/// and trailing edges of a view that was only as tall as its rows, so they were
/// clipped away and could never be clicked. Buttons carry their own geometry,
/// hover state, cursor, and accessibility, and cannot disagree with themselves.
final class DocumentTableView: NSView {

    private(set) var table: TableBlock
    private var blockID: UUID
    private var theme: DocumentTheme

    /// Reports a mutation. The canvas uses this to re-serialise, since edits
    /// inside an attachment never reach the outer text view's change hooks.
    var onChange: ((UUID, TableBlock) -> Void)?

    /// Reports which cell holds the caret, so the formatting panel can act on
    /// this table. `nil` means focus left the grid entirely.
    var onSelectionChange: ((DocumentTableView, TableEditingContext?) -> Void)?

    private var cellViews: [[TableCellTextView]] = []
    private var columnWidths: [CGFloat] = []
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    /// Explicit widths from a drag, keyed by column. Absent means "size to fit".
    private var pinnedWidths: [Int: CGFloat] = [:]

    /// The column border currently being dragged, and where the drag started.
    private var activeResize: (column: Int, startX: CGFloat, startWidth: CGFloat)?

    /// A row or column the user selected by its handle, tinted so it is obvious
    /// what a panel command is about to act on.
    private var selectedRow: Int?
    private var selectedColumn: Int?

    private var rowHandles: [TableGutterButton] = []
    private var columnHandles: [TableGutterButton] = []
    private lazy var addRowButton = makeGutterButton(
        symbol: "plus",
        help: "Add a row at the end of the table"
    ) { [weak self] _ in
        guard let self else { return }
        self.insertRow(at: self.table.rows.count)
    }
    private lazy var addColumnButton = makeGutterButton(
        symbol: "plus",
        help: "Add a column at the end of the table"
    ) { [weak self] _ in
        guard let self else { return }
        self.insertColumn(at: self.table.columnCount)
    }

    private let minimumColumnWidth: CGFloat = 56
    private let cellPadding = NSEdgeInsets(top: 6, left: 9, bottom: 6, right: 9)
    /// The gutter holding the row and column handles.
    private let handleGutter: CGFloat = 15
    /// Room past the table for the "add row" and "add column" buttons. Counted
    /// into the measured size, so they are inside the view and can be clicked.
    private let addControlSpace: CGFloat = 22
    private let addControlSize: CGFloat = 16
    /// How close to a column border counts as grabbing it.
    private let resizeHitSlop: CGFloat = 4

    /// Row heights are measured by laying out every cell, which is far too much
    /// work to repeat for each of layout, drawing, and measurement.
    private var heightCache: [CGFloat: [CGFloat]] = [:]

    var isRightToLeft: Bool {
        let sample = ([table.header] + table.rows)
            .flatMap { $0.cells.map(\.content.plainText) }
            .joined(separator: " ")
        return TextDirection.isRightToLeft(sample)
    }

    convenience init(table: TableBlock, blockID: UUID, theme: DocumentTheme) {
        self.init(frame: .zero)
        self.table = table
        self.blockID = blockID
        self.theme = theme
        wantsLayer = true
        rebuildCells()
    }

    override init(frame frameRect: NSRect) {
        self.table = TableBlock(header: TableRow(cells: [TableCell()]), rows: [], alignments: [.none])
        self.blockID = UUID()
        self.theme = .standard
        super.init(frame: frameRect)
    }

    required init?(coder: NSCoder) {
        self.table = TableBlock(header: TableRow(cells: [TableCell()]), rows: [], alignments: [.none])
        self.blockID = UUID()
        self.theme = .standard
        super.init(coder: coder)
    }

    override var isFlipped: Bool { true }

    // MARK: - Cells

    private var allRows: [TableRow] { [table.header] + table.rows }

    private func rebuildCells() {
        cellViews.flatMap { $0 }.forEach { $0.removeFromSuperview() }
        cellViews = []
        heightCache = [:]

        for (rowIndex, row) in allRows.enumerated() {
            var views: [TableCellTextView] = []
            for (columnIndex, cell) in row.cells.enumerated() {
                let view = TableCellTextView(
                    isHeader: rowIndex == 0,
                    alignment: table.alignments.indices.contains(columnIndex)
                        ? table.alignments[columnIndex]
                        : .none,
                    theme: theme
                )
                view.setCellContent(cell.content)
                view.onEdit = { [weak self] content in
                    self?.updateCell(row: rowIndex, column: columnIndex, content: content)
                }
                view.onNavigate = { [weak self] direction in
                    self?.move(from: (rowIndex, columnIndex), direction: direction)
                }
                view.onFocus = { [weak self] isFocused in
                    self?.cellFocusChanged(row: rowIndex, column: columnIndex, isFocused: isFocused)
                }
                addSubview(view)
                views.append(view)
            }
            cellViews.append(views)
        }

        rebuildHandles()
        needsLayout = true
        needsDisplay = true
    }

    private func updateCell(row: Int, column: Int, content: InlineText) {
        guard row < allRows.count else { return }
        if row == 0 {
            guard column < table.header.cells.count else { return }
            table.header.cells[column].content = content
        } else {
            let bodyRow = row - 1
            guard bodyRow < table.rows.count, column < table.rows[bodyRow].cells.count else { return }
            table.rows[bodyRow].cells[column].content = content
        }
        onChange?(blockID, table)

        // Typing can make a row taller. The height is baked into the
        // attachment's bounds, so TextKit has to be told to ask again —
        // otherwise the text grows underneath a frame that never changes and
        // the cell silently clips what the user is typing.
        let previousHeight = measuredHeight(for: bounds.width)
        heightCache = [:]
        if abs(measuredHeight(for: bounds.width) - previousHeight) > 0.5 {
            invalidateEnclosingLayout()
        }
        invalidateIntrinsicContentSize()
        needsLayout = true
        needsDisplay = true
    }

    /// Re-measures this table inside the canvas that hosts it. An attachment's
    /// size is decided by the layout manager, so growing a row is not something
    /// the view can do on its own.
    private func invalidateEnclosingLayout() {
        var ancestor: NSView? = superview
        while let current = ancestor {
            if let textView = current as? NSTextView {
                if let manager = textView.textLayoutManager {
                    manager.invalidateLayout(for: manager.documentRange)
                } else if let container = textView.textContainer, let manager = textView.layoutManager {
                    manager.invalidateLayout(
                        forCharacterRange: NSRange(location: 0, length: manager.numberOfGlyphs),
                        actualCharacterRange: nil
                    )
                    manager.ensureLayout(for: container)
                }
                textView.needsLayout = true
                return
            }
            ancestor = current.superview
        }
    }

    // MARK: - Selection

    private(set) var focusedCell: (row: Int, column: Int)?

    func currentEditingContext(row: Int, column: Int) -> TableEditingContext {
        let safeRow = min(max(0, row), max(0, allRows.count - 1))
        let safeColumn = min(max(0, column), max(0, table.columnCount - 1))
        let anchor = table.anchor(forRow: safeRow, column: safeColumn) ?? (safeRow, safeColumn)
        let cell = allRows[anchor.row].cells.indices.contains(anchor.column)
            ? allRows[anchor.row].cells[anchor.column]
            : TableCell()

        return TableEditingContext(
            caretRow: safeRow,
            caretColumn: safeColumn,
            rowCount: allRows.count,
            columnCount: table.columnCount,
            alignments: table.alignments,
            cellAlignment: cell.horizontalAlignment,
            cellVerticalAlignment: cell.verticalAlignment,
            isMerged: cell.columnSpan > 1 || cell.rowSpan > 1,
            supportsCellFeatures: true
        )
    }

    private func cellFocusChanged(row: Int, column: Int, isFocused: Bool) {
        guard isFocused else {
            // Focus moving *between* cells fires a resign before the next
            // become, so only report a real departure.
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                guard let focused = self.focusedCell, focused == (row, column) else { return }
                self.focusedCell = nil
                self.onSelectionChange?(self, nil)
                self.needsDisplay = true
            }
            return
        }

        focusedCell = (row, column)
        // Typing in a cell is a different intent from having selected a whole
        // row or column, so entering one clears that selection.
        selectedRow = nil
        selectedColumn = nil
        onSelectionChange?(self, currentEditingContext(row: row, column: column))
        needsDisplay = true
    }

    /// Puts the caret back where it was after the grid rebuilds, so a panel
    /// command doesn't drop the user out of the table.
    private func restoreFocus(to position: (row: Int, column: Int)?) {
        guard let position,
              position.row < cellViews.count,
              position.column < cellViews[position.row].count else { return }
        let target = cellViews[position.row][position.column]
        window?.makeFirstResponder(target)
    }

    // MARK: - Structure

    func insertRow(at index: Int) {
        let cells = (0..<table.columnCount).map { _ in TableCell() }
        let target = max(0, min(index, table.rows.count))
        table.rows.insert(TableRow(cells: cells), at: target)
        commitStructuralChange(focusing: (row: target + 1, column: focusedCell?.column ?? 0))
    }

    func deleteRow(at index: Int) {
        // Row 0 is the header; a table without one stops being a table.
        guard index > 0, index - 1 < table.rows.count else { return }
        table.rows.remove(at: index - 1)
        commitStructuralChange()
    }

    func insertColumn(at index: Int) {
        let target = max(0, min(index, table.columnCount))
        table.alignments.insert(.none, at: target)
        table.header.cells.insert(TableCell(), at: min(target, table.header.cells.count))
        for row in table.rows.indices {
            table.rows[row].cells.insert(TableCell(), at: min(target, table.rows[row].cells.count))
        }
        pinnedWidths = [:]
        commitStructuralChange(focusing: (row: focusedCell?.row ?? 0, column: target))
    }

    func deleteColumn(at index: Int) {
        guard table.columnCount > 1, index >= 0, index < table.columnCount else { return }
        table.alignments.remove(at: index)
        table.header.cells.remove(at: index)
        for row in table.rows.indices where index < table.rows[row].cells.count {
            table.rows[row].cells.remove(at: index)
        }
        pinnedWidths = [:]
        commitStructuralChange()
    }

    func setAlignment(_ alignment: TableColumnAlignment, forColumn index: Int) {
        guard table.alignments.indices.contains(index) else { return }
        table.alignments[index] = alignment
        // A column-wide choice replaces any per-cell overrides in it, which is
        // what "align this column" plainly means.
        mutateColumn(index) { $0.horizontalAlignment = nil }
        commitStructuralChange()
    }

    /// Aligns just the focused cell, leaving the rest of its column alone.
    func setCellAlignment(_ alignment: TableColumnAlignment?) {
        guard let focused = focusedCell else { return }
        mutateCell(row: focused.row, column: focused.column) { $0.horizontalAlignment = alignment }
        commitStructuralChange()
    }

    func setCellVerticalAlignment(_ alignment: TableVerticalAlignment?) {
        guard let focused = focusedCell else { return }
        mutateCell(row: focused.row, column: focused.column) { $0.verticalAlignment = alignment }
        commitStructuralChange()
    }

    /// Whether the focused cell is part of a merge that can be undone.
    var focusedCellIsMerged: Bool {
        guard let focused = focusedCell,
              let anchor = table.anchor(forRow: focused.row, column: focused.column) else { return false }
        let cell = allRows[anchor.row].cells[anchor.column]
        return cell.columnSpan > 1 || cell.rowSpan > 1
    }

    /// Merges the focused cell with the one in the given direction.
    ///
    /// Text from the absorbed cells is kept — appended to the survivor —
    /// because losing what someone typed to a layout command is not a trade
    /// anyone would accept.
    @discardableResult
    func mergeFocusedCell(rowsToAdd: Int, columnsToAdd: Int) -> Bool {
        guard let focused = focusedCell,
              let anchor = table.anchor(forRow: focused.row, column: focused.column) else { return false }

        var grid = allRows
        let cell = grid[anchor.row].cells[anchor.column]
        let newRowSpan = cell.rowSpan + rowsToAdd
        let newColumnSpan = cell.columnSpan + columnsToAdd
        guard newRowSpan >= 1, newColumnSpan >= 1,
              anchor.row + newRowSpan <= grid.count,
              anchor.column + newColumnSpan <= table.columnCount else {
            return false
        }

        var absorbed: [String] = []
        for row in anchor.row..<(anchor.row + newRowSpan) {
            for column in anchor.column..<(anchor.column + newColumnSpan)
            where !(row == anchor.row && column == anchor.column) {
                let text = grid[row].cells[column].content.plainText
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !text.isEmpty { absorbed.append(text) }
                grid[row].cells[column].content = InlineText()
            }
        }

        if !absorbed.isEmpty {
            let existing = grid[anchor.row].cells[anchor.column].content
            let joined = ([existing.plainText.trimmingCharacters(in: .whitespacesAndNewlines)] + absorbed)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
            grid[anchor.row].cells[anchor.column].content = InlineText(plain: joined)
        }

        grid[anchor.row].cells[anchor.column].rowSpan = newRowSpan
        grid[anchor.row].cells[anchor.column].columnSpan = newColumnSpan

        table.header = grid[0]
        table.rows = Array(grid.dropFirst())
        commitStructuralChange(focusing: (row: anchor.row, column: anchor.column))
        return true
    }

    /// Splits the focused merged cell back into ordinary ones.
    @discardableResult
    func unmergeFocusedCell() -> Bool {
        guard let focused = focusedCell,
              let anchor = table.anchor(forRow: focused.row, column: focused.column) else { return false }

        var grid = allRows
        guard grid[anchor.row].cells[anchor.column].columnSpan > 1
                || grid[anchor.row].cells[anchor.column].rowSpan > 1 else {
            return false
        }
        grid[anchor.row].cells[anchor.column].columnSpan = 1
        grid[anchor.row].cells[anchor.column].rowSpan = 1

        table.header = grid[0]
        table.rows = Array(grid.dropFirst())
        commitStructuralChange(focusing: (row: anchor.row, column: anchor.column))
        return true
    }

    private func mutateCell(row: Int, column: Int, _ transform: (inout TableCell) -> Void) {
        guard let anchor = table.anchor(forRow: row, column: column) else { return }
        if anchor.row == 0 {
            guard anchor.column < table.header.cells.count else { return }
            transform(&table.header.cells[anchor.column])
        } else {
            let body = anchor.row - 1
            guard body < table.rows.count, anchor.column < table.rows[body].cells.count else { return }
            transform(&table.rows[body].cells[anchor.column])
        }
    }

    private func mutateColumn(_ column: Int, _ transform: (inout TableCell) -> Void) {
        if column < table.header.cells.count { transform(&table.header.cells[column]) }
        for row in table.rows.indices where column < table.rows[row].cells.count {
            transform(&table.rows[row].cells[column])
        }
    }

    /// What the formatting panel should show for the focused cell.
    var focusedCellState: (horizontal: TableColumnAlignment?, vertical: TableVerticalAlignment?)? {
        guard let focused = focusedCell,
              let anchor = table.anchor(forRow: focused.row, column: focused.column) else { return nil }
        let cell = allRows[anchor.row].cells[anchor.column]
        return (cell.horizontalAlignment, cell.verticalAlignment)
    }

    /// Moves a whole row, so reordering doesn't mean retyping it.
    func moveRow(at index: Int, by offset: Int) {
        let body = index - 1
        let target = body + offset
        guard index > 0, body < table.rows.count, target >= 0, target < table.rows.count else { return }
        let row = table.rows.remove(at: body)
        table.rows.insert(row, at: target)
        commitStructuralChange(focusing: (row: target + 1, column: focusedCell?.column ?? 0))
    }

    func moveColumn(at index: Int, by offset: Int) {
        let target = index + offset
        guard index >= 0, index < table.columnCount, target >= 0, target < table.columnCount else { return }

        table.alignments.swapAt(index, target)
        table.header.cells.swapAt(index, target)
        for row in table.rows.indices where
            index < table.rows[row].cells.count && target < table.rows[row].cells.count {
            table.rows[row].cells.swapAt(index, target)
        }
        pinnedWidths = [:]
        commitStructuralChange(focusing: (row: focusedCell?.row ?? 0, column: target))
    }

    private func commitStructuralChange(focusing preferred: (row: Int, column: Int)? = nil) {
        let previousFocus = preferred ?? focusedCell

        table.normalize()
        onChange?(blockID, table)
        rebuildCells()
        invalidateIntrinsicContentSize()
        invalidateEnclosingLayout()

        if let previousFocus {
            let clamped = (
                row: max(0, min(previousFocus.row, allRows.count - 1)),
                column: max(0, min(previousFocus.column, table.columnCount - 1))
            )
            focusedCell = clamped
            restoreFocus(to: clamped)
            onSelectionChange?(self, currentEditingContext(row: clamped.row, column: clamped.column))
        }
    }

    // MARK: - Navigation

    enum CellDirection {
        case next, previous, nextRow, previousRow
    }

    private func move(from position: (row: Int, column: Int), direction: CellDirection) {
        let rowCount = allRows.count
        let columnCount = table.columnCount
        var row = position.row
        var column = position.column

        switch direction {
        case .next:
            column += 1
            if column >= columnCount {
                column = 0
                row += 1
            }
        case .previous:
            column -= 1
            if column < 0 {
                column = columnCount - 1
                row -= 1
            }
        case .nextRow:
            row += 1
        case .previousRow:
            row -= 1
        }

        // Tabbing off the end grows the table, the way every spreadsheet does.
        // Moving *up* off the top does not — there is nothing above a header.
        if row >= rowCount {
            guard direction != .previousRow else { return }
            insertRow(at: table.rows.count)
            row = allRows.count - 1
            if direction == .next { column = 0 }
        }
        guard row >= 0, column >= 0, row < cellViews.count, column < cellViews[row].count else { return }

        let target = cellViews[row][column]
        window?.makeFirstResponder(target)
        target.setSelectedRange(NSRange(location: target.string.count, length: 0))
    }

    // MARK: - Layout

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: measuredHeight(for: bounds.width))
    }

    /// The height this table needs at a given width, used both for layout and
    /// to tell TextKit how much room to leave for the attachment. The handle
    /// gutter and the trailing "add" controls are part of it — a control the
    /// measurement forgets is a control the view clips away.
    func measuredHeight(for width: CGFloat) -> CGFloat {
        let widths = resolvedColumnWidths(for: width)
        return handleGutter + rowHeights(columnWidths: widths).reduce(0, +) + addControlSpace
    }

    /// Width available to the columns themselves.
    private func contentWidth(for totalWidth: CGFloat) -> CGFloat {
        max(minimumColumnWidth, totalWidth - handleGutter - addControlSpace)
    }

    private func resolvedColumnWidths(for totalWidth: CGFloat) -> [CGFloat] {
        let count = max(1, table.columnCount)
        let available = max(minimumColumnWidth * CGFloat(count), contentWidth(for: totalWidth))

        // Columns the user has sized keep that size; the rest share what's left
        // in proportion to how much text they hold.
        var widths = [CGFloat](repeating: 0, count: count)
        var flexible: [Int] = []
        var used: CGFloat = 0

        for index in 0..<count {
            if let pinned = pinnedWidths[index] {
                widths[index] = max(minimumColumnWidth, pinned)
                used += widths[index]
            } else {
                flexible.append(index)
            }
        }

        guard !flexible.isEmpty else { return widths }

        let remaining = max(CGFloat(flexible.count) * minimumColumnWidth, available - used)
        let demands = flexible.map { index -> CGFloat in
            let longest = allRows.compactMap { row -> Int? in
                guard index < row.cells.count else { return nil }
                return row.cells[index].content.plainText.count
            }.max() ?? 1
            return max(1, CGFloat(longest))
        }
        let totalDemand = demands.reduce(0, +)

        for (offset, index) in flexible.enumerated() {
            let share = totalDemand > 0 ? demands[offset] / totalDemand : 1 / CGFloat(flexible.count)
            widths[index] = max(minimumColumnWidth, remaining * share)
        }
        return widths
    }

    private func rowHeights(columnWidths widths: [CGFloat]) -> [CGFloat] {
        let key = (widths.reduce(0, +) * 4).rounded() / 4
        if let cached = heightCache[key] { return cached }

        let grid = allRows
        // Only cells that live in a single row decide that row's height; a
        // cell spanning several is satisfied by their total, handled below.
        var heights = grid.enumerated().map { rowIndex, row -> CGFloat in
            var tallest: CGFloat = 24
            for column in 0..<table.columnCount {
                guard rowIndex < cellViews.count, column < cellViews[rowIndex].count,
                      column < row.cells.count else { continue }
                let cell = row.cells[column]
                guard !cell.isCovered, cell.rowSpan == 1 else { continue }

                let width = spannedWidth(widths, from: column, span: cell.columnSpan)
                    - cellPadding.left - cellPadding.right
                let height = cellViews[rowIndex][column].height(forWidth: max(20, width))
                tallest = max(tallest, height + cellPadding.top + cellPadding.bottom)
            }
            return tallest
        }

        // Now make sure every spanning cell fits inside the rows it covers,
        // growing the last of them when it doesn't.
        for (rowIndex, row) in grid.enumerated() {
            for column in 0..<min(table.columnCount, row.cells.count) {
                let cell = row.cells[column]
                guard !cell.isCovered, cell.rowSpan > 1,
                      rowIndex < cellViews.count, column < cellViews[rowIndex].count else { continue }

                let width = spannedWidth(widths, from: column, span: cell.columnSpan)
                    - cellPadding.left - cellPadding.right
                let needed = cellViews[rowIndex][column].height(forWidth: max(20, width))
                    + cellPadding.top + cellPadding.bottom

                let last = min(rowIndex + cell.rowSpan, heights.count) - 1
                guard last >= rowIndex else { continue }
                let available = heights[rowIndex...last].reduce(0, +)
                if needed > available {
                    heights[last] += needed - available
                }
            }
        }

        heightCache[key] = heights
        return heights
    }

    private func spannedWidth(_ widths: [CGFloat], from column: Int, span: Int) -> CGFloat {
        let upper = min(column + max(1, span), widths.count)
        guard column < upper else { return minimumColumnWidth }
        return widths[column..<upper].reduce(0, +)
    }

    private func spannedHeight(_ heights: [CGFloat], from row: Int, span: Int) -> CGFloat {
        let upper = min(row + max(1, span), heights.count)
        guard row < upper else { return 24 }
        return heights[row..<upper].reduce(0, +)
    }

    /// Where the grid itself starts, with the handle gutter before it.
    private func tableOrigin(tableWidth: CGFloat) -> CGPoint {
        CGPoint(
            x: isRightToLeft ? bounds.width - handleGutter - tableWidth : handleGutter,
            y: handleGutter
        )
    }

    override func layout() {
        super.layout()

        let widths = resolvedColumnWidths(for: bounds.width)
        columnWidths = widths
        let heights = rowHeights(columnWidths: widths)
        let mirrored = isRightToLeft
        let tableWidth = widths.reduce(0, +)
        let origin = tableOrigin(tableWidth: tableWidth)

        let grid = allRows
        var y = origin.y
        for (rowIndex, rowHeight) in heights.enumerated() {
            var x: CGFloat = mirrored ? origin.x + tableWidth : origin.x
            for column in 0..<table.columnCount {
                guard rowIndex < cellViews.count, column < cellViews[rowIndex].count else { continue }
                let width = column < widths.count ? widths[column] : minimumColumnWidth
                let cell = rowIndex < grid.count && column < grid[rowIndex].cells.count
                    ? grid[rowIndex].cells[column]
                    : TableCell()

                defer { x = mirrored ? x - width : x + width }

                // A covered position has no cell of its own; the merged cell
                // that owns it is drawn from its own anchor.
                guard !cell.isCovered else {
                    cellViews[rowIndex][column].isHidden = true
                    continue
                }
                cellViews[rowIndex][column].isHidden = false

                let boxWidth = spannedWidth(widths, from: column, span: cell.columnSpan)
                let boxHeight = spannedHeight(heights, from: rowIndex, span: cell.rowSpan)
                let boxX = mirrored ? x - boxWidth : x

                let innerWidth = max(10, boxWidth - cellPadding.left - cellPadding.right)
                let available = max(12, boxHeight - cellPadding.top - cellPadding.bottom)
                let contentHeight = min(
                    available,
                    max(12, cellViews[rowIndex][column].height(forWidth: innerWidth))
                )

                // `nil` keeps the long-standing behaviour of filling the cell
                // from the top; an explicit choice does what it says.
                let cellY: CGFloat
                switch cell.verticalAlignment {
                case .middle: cellY = y + (boxHeight - contentHeight) / 2
                case .bottom: cellY = y + boxHeight - cellPadding.bottom - contentHeight
                case .top, .none: cellY = y + cellPadding.top
                }

                cellViews[rowIndex][column].frame = NSRect(
                    x: boxX + cellPadding.left,
                    y: cellY,
                    width: innerWidth,
                    height: cell.verticalAlignment == nil ? available : contentHeight
                )
            }
            y += rowHeight
        }

        layoutControls(origin: origin, widths: widths, heights: heights)
    }

    // MARK: - Gutter controls

    private func makeGutterButton(
        symbol: String,
        help: String,
        action: @escaping (TableGutterButton) -> Void
    ) -> TableGutterButton {
        let button = TableGutterButton(symbol: symbol, help: help, action: action)
        addSubview(button)
        return button
    }

    private func rebuildHandles() {
        (rowHandles + columnHandles).forEach { $0.removeFromSuperview() }
        rowHandles = []
        columnHandles = []

        for rowIndex in allRows.indices {
            let handle = makeGutterButton(
                symbol: "line.3.horizontal",
                help: rowIndex == 0
                    ? "Header row — click for row actions"
                    : "Row \(rowIndex) — click for row actions"
            ) { [weak self] button in
                self?.showRowMenu(for: rowIndex, from: button)
            }
            handle.orientation = .row
            rowHandles.append(handle)
        }

        for columnIndex in 0..<table.columnCount {
            let handle = makeGutterButton(
                symbol: "line.3.horizontal",
                help: "Column \(columnIndex + 1) — click for column actions"
            ) { [weak self] button in
                self?.showColumnMenu(for: columnIndex, from: button)
            }
            handle.orientation = .column
            columnHandles.append(handle)
        }

        // Keep the add buttons on top of the freshly added handles.
        addRowButton.removeFromSuperview()
        addColumnButton.removeFromSuperview()
        addSubview(addRowButton)
        addSubview(addColumnButton)
        updateControlVisibility()
    }

    private func layoutControls(origin: CGPoint, widths: [CGFloat], heights: [CGFloat]) {
        let mirrored = isRightToLeft
        let tableWidth = widths.reduce(0, +)
        let tableHeight = heights.reduce(0, +)

        var y = origin.y
        for (index, height) in heights.enumerated() where index < rowHandles.count {
            let x = mirrored ? origin.x + tableWidth + 2 : origin.x - handleGutter + 2
            rowHandles[index].frame = NSRect(
                x: x,
                y: y + max(0, (height - handleGutter) / 2),
                width: handleGutter - 4,
                height: min(height - 2, handleGutter)
            )
            y += height
        }

        var x: CGFloat = mirrored ? origin.x + tableWidth : origin.x
        for (index, width) in widths.enumerated() where index < columnHandles.count {
            let left = mirrored ? x - width : x
            columnHandles[index].frame = NSRect(
                x: left + max(0, (width - handleGutter) / 2),
                y: origin.y - handleGutter + 2,
                width: min(width - 2, handleGutter),
                height: handleGutter - 4
            )
            x = mirrored ? x - width : x + width
        }

        addColumnButton.frame = NSRect(
            x: mirrored ? origin.x - addControlSpace + 2 : origin.x + tableWidth + 3,
            y: origin.y + max(0, ((heights.first ?? 24) - addControlSize) / 2),
            width: addControlSize,
            height: addControlSize
        )
        addRowButton.frame = NSRect(
            x: origin.x + max(0, ((widths.first ?? minimumColumnWidth) - addControlSize) / 2),
            y: origin.y + tableHeight + 3,
            width: addControlSize,
            height: addControlSize
        )
    }

    private func updateControlVisibility() {
        let visible = isHovered || focusedCell != nil
        (rowHandles + columnHandles).forEach { $0.isHidden = !visible }
        addRowButton.isHidden = !visible
        addColumnButton.isHidden = !visible
    }

    private func showRowMenu(for index: Int, from button: NSView) {
        selectedRow = index
        selectedColumn = nil
        needsDisplay = true

        let menu = NSMenu()
        if index > 0 {
            menu.addItem(withTitle: "Insert Row Above", action: #selector(menuInsertRowAbove), keyEquivalent: "")
        }
        menu.addItem(withTitle: "Insert Row Below", action: #selector(menuInsertRowBelow), keyEquivalent: "")
        menu.addItem(.separator())
        if index > 1 {
            menu.addItem(withTitle: "Move Row Up", action: #selector(menuMoveRowUp), keyEquivalent: "")
        }
        if index > 0, index < allRows.count - 1 {
            menu.addItem(withTitle: "Move Row Down", action: #selector(menuMoveRowDown), keyEquivalent: "")
        }
        if index > 0 {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete Row", action: #selector(menuDeleteRow), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    private func showColumnMenu(for index: Int, from button: NSView) {
        selectedColumn = index
        selectedRow = nil
        needsDisplay = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Insert Column Before", action: #selector(menuInsertColumnBefore), keyEquivalent: "")
        menu.addItem(withTitle: "Insert Column After", action: #selector(menuInsertColumnAfter), keyEquivalent: "")
        menu.addItem(.separator())
        if index > 0 {
            menu.addItem(withTitle: "Move Column Left", action: #selector(menuMoveColumnLeft), keyEquivalent: "")
        }
        if index < table.columnCount - 1 {
            menu.addItem(withTitle: "Move Column Right", action: #selector(menuMoveColumnRight), keyEquivalent: "")
        }
        menu.addItem(.separator())

        let current = table.alignments.indices.contains(index) ? table.alignments[index] : .none
        for (title, alignment) in [
            ("Align Left", TableColumnAlignment.left),
            ("Align Centre", .center),
            ("Align Right", .right),
            ("No Alignment", .none)
        ] {
            let item = menu.addItem(
                withTitle: title,
                action: #selector(menuSetAlignment(_:)),
                keyEquivalent: ""
            )
            item.representedObject = alignment.rawValue
            item.state = current == alignment ? .on : .off
        }

        if table.columnCount > 1 {
            menu.addItem(.separator())
            menu.addItem(withTitle: "Delete Column", action: #selector(menuDeleteColumn), keyEquivalent: "")
        }
        menu.items.forEach { $0.target = self }
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height), in: button)
    }

    @objc private func menuInsertRowAbove() {
        guard let row = selectedRow else { return }
        insertRow(at: row - 1)
    }

    @objc private func menuInsertRowBelow() {
        guard let row = selectedRow else { return }
        insertRow(at: row)
    }

    @objc private func menuMoveRowUp() {
        guard let row = selectedRow else { return }
        moveRow(at: row, by: -1)
    }

    @objc private func menuMoveRowDown() {
        guard let row = selectedRow else { return }
        moveRow(at: row, by: 1)
    }

    @objc private func menuDeleteRow() {
        guard let row = selectedRow else { return }
        selectedRow = nil
        deleteRow(at: row)
    }

    @objc private func menuInsertColumnBefore() {
        guard let column = selectedColumn else { return }
        insertColumn(at: column)
    }

    @objc private func menuInsertColumnAfter() {
        guard let column = selectedColumn else { return }
        insertColumn(at: column + 1)
    }

    @objc private func menuMoveColumnLeft() {
        guard let column = selectedColumn else { return }
        moveColumn(at: column, by: -1)
    }

    @objc private func menuMoveColumnRight() {
        guard let column = selectedColumn else { return }
        moveColumn(at: column, by: 1)
    }

    @objc private func menuDeleteColumn() {
        guard let column = selectedColumn else { return }
        selectedColumn = nil
        deleteColumn(at: column)
    }

    @objc private func menuSetAlignment(_ sender: NSMenuItem) {
        guard let column = selectedColumn,
              let raw = sender.representedObject as? String,
              let alignment = TableColumnAlignment(rawValue: raw) else { return }
        setAlignment(alignment, forColumn: column)
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        let widths = columnWidths.isEmpty ? resolvedColumnWidths(for: bounds.width) : columnWidths
        let heights = rowHeights(columnWidths: widths)
        let tableWidth = widths.reduce(0, +)
        let tableHeight = heights.reduce(0, +)
        let origin = tableOrigin(tableWidth: tableWidth)

        // Header band.
        if let headerHeight = heights.first {
            NSColor.quaternaryLabelColor.withAlphaComponent(0.10).setFill()
            NSRect(x: origin.x, y: origin.y, width: tableWidth, height: headerHeight).fill()
        }

        drawSelectionTint(origin: origin, widths: widths, heights: heights)

        NSColor.separatorColor.setStroke()
        let border = NSBezierPath()
        border.lineWidth = 1

        // The outline is always whole; the internal lines are drawn per cell
        // edge, so a merged cell reads as one box instead of keeping the seams
        // of the cells it swallowed.
        border.appendRect(NSRect(x: origin.x, y: origin.y, width: tableWidth, height: tableHeight))

        let grid = allRows
        let mirroredGrid = isRightToLeft
        var y = origin.y
        for (rowIndex, rowHeight) in heights.enumerated() {
            var x: CGFloat = mirroredGrid ? origin.x + tableWidth : origin.x
            for column in 0..<table.columnCount {
                let width = column < widths.count ? widths[column] : minimumColumnWidth
                defer { x = mirroredGrid ? x - width : x + width }

                guard rowIndex < grid.count, column < grid[rowIndex].cells.count else { continue }
                let cell = grid[rowIndex].cells[column]
                guard !cell.isCovered else { continue }

                let boxWidth = spannedWidth(widths, from: column, span: cell.columnSpan)
                let boxHeight = spannedHeight(heights, from: rowIndex, span: cell.rowSpan)
                let boxX = mirroredGrid ? x - boxWidth : x

                border.appendRect(NSRect(x: boxX, y: y, width: boxWidth, height: boxHeight))
            }
            y += rowHeight
        }
        border.stroke()

        drawFocusRing(origin: origin, widths: widths, heights: heights)
    }

    private func drawSelectionTint(origin: CGPoint, widths: [CGFloat], heights: [CGFloat]) {
        NSColor.controlAccentColor.withAlphaComponent(0.10).setFill()

        if let row = selectedRow, row < heights.count {
            let y = origin.y + heights.prefix(row).reduce(0, +)
            NSRect(x: origin.x, y: y, width: widths.reduce(0, +), height: heights[row]).fill()
        }
        if let column = selectedColumn, column < widths.count {
            let leading = widths.prefix(column).reduce(0, +)
            let x = isRightToLeft
                ? origin.x + widths.reduce(0, +) - leading - widths[column]
                : origin.x + leading
            NSRect(x: x, y: origin.y, width: widths[column], height: heights.reduce(0, +)).fill()
        }
    }

    /// A ring around the cell holding the caret. Without it there is no way to
    /// tell which cell a panel command is about to change.
    private func drawFocusRing(origin: CGPoint, widths: [CGFloat], heights: [CGFloat]) {
        guard let focused = focusedCell,
              focused.row < heights.count,
              focused.column < widths.count,
              window?.firstResponder is TableCellTextView else { return }

        let leading = widths.prefix(focused.column).reduce(0, +)
        let x = isRightToLeft
            ? origin.x + widths.reduce(0, +) - leading - widths[focused.column]
            : origin.x + leading
        let y = origin.y + heights.prefix(focused.row).reduce(0, +)

        let rect = NSRect(x: x, y: y, width: widths[focused.column], height: heights[focused.row])
            .insetBy(dx: 0.5, dy: 0.5)
        NSColor.controlAccentColor.withAlphaComponent(0.85).setStroke()
        let ring = NSBezierPath(rect: rect)
        ring.lineWidth = 1.5
        ring.stroke()
    }

    // MARK: - Hover, resizing, and hit testing

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }

        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        updateControlVisibility()
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        updateControlVisibility()
        needsDisplay = true
    }

    /// The x position of each column's outer border — the edge you drag to
    /// resize that column. Mirrored along with the grid, so the border you
    /// grab in a Persian table belongs to the column you are pointing at.
    private func columnBorderPositions(widths: [CGFloat], origin: CGPoint) -> [(column: Int, x: CGFloat)] {
        let tableWidth = widths.reduce(0, +)
        var result: [(Int, CGFloat)] = []
        var consumed: CGFloat = 0
        for (index, width) in widths.enumerated() {
            consumed += width
            result.append((
                index,
                isRightToLeft ? origin.x + tableWidth - consumed : origin.x + consumed
            ))
        }
        return result
    }

    override func resetCursorRects() {
        super.resetCursorRects()
        guard !cellViews.isEmpty else { return }

        let widths = columnWidths.isEmpty ? resolvedColumnWidths(for: bounds.width) : columnWidths
        let heights = rowHeights(columnWidths: widths)
        let origin = tableOrigin(tableWidth: widths.reduce(0, +))
        let tableHeight = heights.reduce(0, +)

        for border in columnBorderPositions(widths: widths, origin: origin) {
            addCursorRect(
                NSRect(
                    x: border.x - resizeHitSlop,
                    y: origin.y,
                    width: resizeHitSlop * 2,
                    height: tableHeight
                ),
                cursor: .resizeLeftRight
            )
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let widths = columnWidths.isEmpty ? resolvedColumnWidths(for: bounds.width) : columnWidths
        let heights = rowHeights(columnWidths: widths)
        let origin = tableOrigin(tableWidth: widths.reduce(0, +))
        let tableHeight = heights.reduce(0, +)

        // Dragging a column border resizes that column. This is what
        // `pinnedWidths` was always for; nothing had ever been able to set it,
        // so every column was stuck at its computed share.
        if point.y >= origin.y, point.y <= origin.y + tableHeight {
            for border in columnBorderPositions(widths: widths, origin: origin)
            where abs(point.x - border.x) <= resizeHitSlop {
                activeResize = (
                    column: border.column,
                    startX: point.x,
                    startWidth: widths.indices.contains(border.column)
                        ? widths[border.column]
                        : minimumColumnWidth
                )
                return
            }
        }

        // Clicking anywhere in a cell's row/column band puts the caret in that
        // cell, including the padding around the text. Landing on a table and
        // having nothing happen is the kind of thing that makes an editor feel
        // dead.
        if let cell = cell(at: point, widths: widths, heights: heights, origin: origin) {
            window?.makeFirstResponder(cell)
            return
        }

        super.mouseDown(with: event)
    }

    override func mouseDragged(with event: NSEvent) {
        guard let resize = activeResize else {
            super.mouseDragged(with: event)
            return
        }
        let point = convert(event.locationInWindow, from: nil)
        let delta = isRightToLeft ? resize.startX - point.x : point.x - resize.startX
        pinnedWidths[resize.column] = max(minimumColumnWidth, resize.startWidth + delta)

        heightCache = [:]
        invalidateIntrinsicContentSize()
        invalidateEnclosingLayout()
        needsLayout = true
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        if activeResize != nil {
            activeResize = nil
            window?.invalidateCursorRects(for: self)
            return
        }
        super.mouseUp(with: event)
    }

    private func cell(
        at point: NSPoint,
        widths: [CGFloat],
        heights: [CGFloat],
        origin: CGPoint
    ) -> TableCellTextView? {
        let tableWidth = widths.reduce(0, +)
        guard point.x >= origin.x, point.x <= origin.x + tableWidth, point.y >= origin.y else { return nil }

        var y = origin.y
        var rowIndex: Int?
        for (index, height) in heights.enumerated() {
            if point.y >= y, point.y < y + height {
                rowIndex = index
                break
            }
            y += height
        }
        guard let row = rowIndex else { return nil }

        var x = isRightToLeft ? origin.x + tableWidth : origin.x
        for (index, width) in widths.enumerated() {
            let left = isRightToLeft ? x - width : x
            if point.x >= left, point.x < left + width {
                guard row < cellViews.count, index < cellViews[row].count else { return nil }
                return cellViews[row][index]
            }
            x = isRightToLeft ? x - width : x + width
        }
        return nil
    }
}

/// A control in the table's gutter. A real button, so it hit-tests where it
/// draws and reports itself to accessibility.
final class TableGutterButton: NSView {
    enum Orientation { case row, column, free }

    var orientation: Orientation = .free
    private let symbol: String
    private let action: (TableGutterButton) -> Void
    private var isHovered = false
    private var trackingArea: NSTrackingArea?

    init(symbol: String, help: String, action: @escaping (TableGutterButton) -> Void) {
        self.symbol = symbol
        self.action = action
        super.init(frame: .zero)
        wantsLayer = true
        toolTip = help
        setAccessibilityLabel(help)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isFlipped: Bool { true }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect],
            owner: self
        )
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
        needsDisplay = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        action(self)
    }

    override func draw(_ dirtyRect: NSRect) {
        let radius = min(bounds.width, bounds.height) / 2
        let path = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
        (isHovered
            ? NSColor.controlAccentColor.withAlphaComponent(0.85)
            : NSColor.tertiaryLabelColor.withAlphaComponent(0.55)).setFill()
        path.fill()

        guard symbol == "plus" else { return }
        NSColor.white.setStroke()
        let glyph = NSBezierPath()
        glyph.lineWidth = 1.5
        glyph.lineCapStyle = .round
        let inset = min(bounds.width, bounds.height) * 0.3
        glyph.move(to: NSPoint(x: bounds.midX, y: bounds.minY + inset))
        glyph.line(to: NSPoint(x: bounds.midX, y: bounds.maxY - inset))
        glyph.move(to: NSPoint(x: bounds.minX + inset, y: bounds.midY))
        glyph.line(to: NSPoint(x: bounds.maxX - inset, y: bounds.midY))
        glyph.stroke()
    }
}

/// One cell. A real text view, so a cell behaves like text — selection, undo,
/// IME, and bidirectional layout all included.
final class TableCellTextView: NSTextView {
    var onEdit: ((InlineText) -> Void)?
    var onNavigate: ((DocumentTableView.CellDirection) -> Void)?
    var onFocus: ((Bool) -> Void)?

    private var isHeader = false
    private var theme: DocumentTheme = .standard

    /// Cells are built on an explicit TextKit 1 stack.
    ///
    /// The default stack a bare `NSTextView` gets is TextKit 2, where
    /// `textStorage` and `layoutManager` are nil — so setting cell content did
    /// nothing and measuring a row's height silently returned a fixed
    /// fallback. A cell is a small, self-contained piece of text; TextKit 1 is
    /// the right tool for it, and the canvas around it stays on TextKit 2.
    convenience init(isHeader: Bool, alignment: TableColumnAlignment, theme: DocumentTheme) {
        let storage = NSTextStorage()
        let layout = NSLayoutManager()
        let container = NSTextContainer(size: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        container.widthTracksTextView = true
        container.lineFragmentPadding = 0
        layout.addTextContainer(container)
        storage.addLayoutManager(layout)

        self.init(frame: .zero, textContainer: container)
        self.isHeader = isHeader
        self.theme = theme
        configure(alignment: alignment, theme: theme)
    }

    override init(frame frameRect: NSRect, textContainer container: NSTextContainer?) {
        super.init(frame: frameRect, textContainer: container)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    private func configure(alignment: TableColumnAlignment, theme: DocumentTheme) {
        isEditable = true
        isSelectable = true
        isRichText = true
        drawsBackground = false
        allowsUndo = true
        textContainerInset = .zero
        textContainer?.lineFragmentPadding = 0
        textContainer?.widthTracksTextView = true
        isVerticallyResizable = false
        isHorizontallyResizable = false
        isAutomaticQuoteSubstitutionEnabled = false
        isAutomaticDashSubstitutionEnabled = false
        isAutomaticTextReplacementEnabled = false
        font = MarkowskiTypography.font(
            size: theme.bodySize * 0.95,
            weight: isHeader ? .semibold : .regular,
            for: ""
        )
        delegate = self

        let style = NSMutableParagraphStyle()
        switch alignment {
        case .center: style.alignment = .center
        case .right: style.alignment = .right
        default: style.alignment = .natural
        }
        defaultParagraphStyle = style
    }

    func setCellContent(_ content: InlineText) {
        let attributed = NSMutableAttributedString()
        for run in content.runs {
            var traits: NSFontTraitMask = []
            if run.style.contains(.bold) { traits.insert(.boldFontMask) }
            if run.style.contains(.italic) { traits.insert(.italicFontMask) }

            var runFont: NSFont
            if run.style.contains(.code) {
                runFont = .monospacedSystemFont(ofSize: (font?.pointSize ?? 13) * 0.95, weight: .regular)
            } else {
                runFont = MarkowskiTypography.font(
                    size: (font?.pointSize ?? 13),
                    weight: isHeader || run.style.contains(.bold) ? .semibold : .regular,
                    for: run.text
                )
                if !traits.isEmpty {
                    runFont = NSFontManager.shared.convert(runFont, toHaveTrait: traits)
                }
            }

            var attributes: [NSAttributedString.Key: Any] = [
                .font: runFont,
                .foregroundColor: NSColor.labelColor,
                .mvInlineStyle: run.style.rawValue
            ]
            if run.style.contains(.strikethrough) {
                attributes[.strikethroughStyle] = NSUnderlineStyle.single.rawValue
            }
            // A styled cell should look styled. These two were the only inline
            // styles the grid rendered as nothing, so `code` and `highlight`
            // survived a save but were invisible while editing.
            if run.style.contains(.highlight) {
                attributes[.backgroundColor] = NSColor.systemYellow.withAlphaComponent(0.32)
            } else if run.style.contains(.code) {
                attributes[.backgroundColor] = NSColor.quaternaryLabelColor.withAlphaComponent(0.14)
            }
            if let link = run.link {
                attributes[.link] = link
                attributes[.foregroundColor] = NSColor.linkColor
                attributes[.underlineStyle] = NSUnderlineStyle.single.rawValue
            }
            attributed.append(NSAttributedString(string: run.text, attributes: attributes))
        }

        if let style = defaultParagraphStyle, attributed.length > 0 {
            attributed.addAttribute(.paragraphStyle, value: style, range: attributed.fullRange)
        }
        textStorage?.setAttributedString(attributed)
    }

    var cellContent: InlineText {
        guard let storage = textStorage else { return InlineText() }
        return RichTextReader.inlineText(from: storage, baseIsBold: isHeader)
    }

    override func becomeFirstResponder() -> Bool {
        let accepted = super.becomeFirstResponder()
        if accepted { onFocus?(true) }
        return accepted
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned { onFocus?(false) }
        return resigned
    }

    func height(forWidth width: CGFloat) -> CGFloat {
        guard let manager = layoutManager, let container = textContainer else { return 18 }
        container.size = NSSize(width: width, height: .greatestFiniteMagnitude)
        manager.ensureLayout(for: container)
        return max(18, manager.usedRect(for: container).height)
    }

    /// Tab moves between cells; Return moves down a row. Neither belongs in the
    /// text of a cell.
    override func insertTab(_ sender: Any?) {
        onNavigate?(.next)
    }

    override func insertBacktab(_ sender: Any?) {
        onNavigate?(.previous)
    }

    override func insertNewline(_ sender: Any?) {
        onNavigate?(.nextRow)
    }

    /// Up and down move between rows once the caret is at the edge of the
    /// cell's own text — the behaviour every grid has, and the reason arrow
    /// keys used to trap the caret inside one cell forever.
    override func moveUp(_ sender: Any?) {
        guard isAtFirstLine else {
            super.moveUp(sender)
            return
        }
        onNavigate?(.previousRow)
    }

    override func moveDown(_ sender: Any?) {
        guard isAtLastLine else {
            super.moveDown(sender)
            return
        }
        onNavigate?(.nextRow)
    }

    private var isAtFirstLine: Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var effective = NSRange()
        manager.lineFragmentRect(
            forGlyphAt: min(selectedRange().location, manager.numberOfGlyphs - 1),
            effectiveRange: &effective
        )
        return effective.location == 0
    }

    private var isAtLastLine: Bool {
        guard let manager = layoutManager, manager.numberOfGlyphs > 0 else { return true }
        var effective = NSRange()
        manager.lineFragmentRect(
            forGlyphAt: min(selectedRange().location, manager.numberOfGlyphs - 1),
            effectiveRange: &effective
        )
        return NSMaxRange(effective) >= manager.numberOfGlyphs
    }
}

extension TableCellTextView: NSTextViewDelegate {
    func textDidChange(_ notification: Notification) {
        onEdit?(cellContent)
    }
}
