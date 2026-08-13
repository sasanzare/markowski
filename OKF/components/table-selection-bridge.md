---
type: Swift Type
title: TableSelectionBridge
description: Connects the formatting panel to whichever table holds the caret, across both the canvas and Source mode.
resource: MarkView/Views/Editing/Canvas/TableSelectionBridge.swift
tags: [component, editing, table]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-13T00:00:00Z }
---

# Why it exists

A table in the canvas is an `NSTextAttachment` holding a live grid. The outer
text view's caret is never *inside* it, so `MarkdownFormatter.tableContext` —
which finds a table by reading Markdown source around an offset — can never
match. When tables became objects, the panel's table section went permanently
disabled without anything reporting an error.

# How it works

`TableEditingContext` is the shape the panel understands: caret row and
column, row and column counts, alignments, and whether a delete is legal.
Both surfaces produce one:

- **Canvas** — a focused `TableCellTextView` reports through its grid, the
  attachment, and the canvas coordinator into `TableSelectionBridge.focus`.
- **Source** — `MarkdownFormatter.TableContext.editingContext` converts the
  text-based finder's result into the same shape.

`DocumentView.currentTableContext` prefers the live one: if a grid holds
focus, that is unambiguously the table the user means.

Commands travel back the same way. `applyFormatCommand` offers each table
command to the bridge first; only if the bridge declines (no live table) does
it fall through to the Markdown-text implementation.

# Details that matter

- **`release` is grid-specific.** Moving between two tables fires the old
  grid's resign *after* the new grid's become, so a blind clear would blank
  the panel exactly when a table had just been selected.
- **The context is re-published after a structural change**, so the panel
  shows the table as it now is — and the grid restores focus to the same cell
  so a panel command doesn't drop the user out of the table.
- **The two alignment enums are bridged**, not merged: `MarkdownFormatter` has
  its own from the text era, and both describe the same four states.
