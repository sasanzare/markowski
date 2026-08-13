---
type: View
title: DocumentTableView
description: A table embedded in the canvas as a real grid — each cell its own text view, structural edits mutating the model.
resource: MarkView/Views/Editing/Canvas/DocumentTableView.swift
tags: [view, editing, canvas, table]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-13T00:00:00Z }
---

# What it does

Draws and edits a `TableBlock` as a grid. It reaches the canvas through
`TableAttachment`, an `NSTextAttachment` whose view provider loads this view,
so a table occupies exactly one character in the text storage and behaves as
an object rather than as rows of tab-separated text.

That earlier arrangement was the problem: cell boundaries were a fiction
maintained by tab stops at fixed 150pt intervals, a typed tab created a
column, and a return destroyed the row.

# Cells

Each cell is a `TableCellTextView` — a real text view, so selection, undo,
IME, and bidirectional layout come for free. Tab and Shift-Tab move between
cells, Return moves down a row, and tabbing off the last cell adds a row the
way a spreadsheet does. None of those keys can end up as characters in a cell.

Cells are built on an **explicit TextKit 1 stack**. The default stack for a
bare `NSTextView` is TextKit 2, where `textStorage` and `layoutManager` are
nil — so `setCellContent` silently did nothing and `height(forWidth:)`
silently returned a constant, making every row the same height. The canvas
around the table stays on TextKit 2.

# Layout

Columns the user has sized keep that width; the rest share what is left in
proportion to how much text they hold, subject to a minimum. Rows are as tall
as their tallest cell. A table whose content is Persian mirrors its column
order.

# Structure

`insertRow`, `deleteRow`, `insertColumn`, `deleteColumn`, and `setAlignment`
mutate the `TableBlock` and report it through `onChange`, which the canvas
uses to re-serialise — edits inside an attachment never reach the outer text
view's change hooks, so the attachment reports for itself. The header row is
not deletable; a table without one stops being a table.

Add-row and add-column affordances appear on hover, so a document reads as a
document until you reach for it.
