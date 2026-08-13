---
type: View
title: FormattingSidebar
description: The left formatting pane — text style, inline format, lists, insertions, direction, table editing, and Persian text tools.
resource: MarkView/Views/Editing/FormattingSidebar.swift
tags: [view, editing, sidebar, persian]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-12T00:00:00Z }
---

# What it does

A left pane, toggled by the toolbar's `sidebar.left` button or ⌘⌥F,
holding every formatting action: text style (H1–H3 and body), inline
format (bold, italic, strikethrough, code, highlight), lists (bulleted,
numbered, task, quote), insertions (link, code block, rule, table),
paragraph direction, table editing, and the Persian text tools.

It emits `FormatCommand` values and holds no document state of its own —
see [the editing architecture](../architecture/editing.md) for how those
are applied.

# Table controls are contextual

The table section is driven by `MarkdownFormatter.TableContext`, which is
non-nil only when the caret is inside a GFM table. When it is, the panel
names the row and column the caret is in, and the alignment buttons show
the current column's alignment as selected. Deleting the header row and
deleting the last remaining column are disabled rather than hidden, so
the controls don't move around under the pointer.

# Persian tools

Surfaced always, but the section header marks when the current scope
actually contains Persian. The actions map onto
[PersianTextTools](../components/markdown-formatter.md): a single "Clean
up everything", plus individual letter normalisation, نیم‌فاصله
insertion, digit conversion both ways, Persian punctuation, and RTL/LTR
pinning for neutral runs.
