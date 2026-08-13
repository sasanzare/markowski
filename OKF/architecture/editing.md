---
type: Architecture
title: Editing
description: The formatting panel, editing a block directly in the preview, and how both write to the document without losing the rest of it.
resource: MarkView/Services/Editing/MarkdownFormatter.swift
tags: [architecture, editing, markdown]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-12T00:00:00Z }
---

# Two editing surfaces, one document

`DocumentView` owns `document.text` and is the only thing that writes to
it, through `applyEditWithUndo` — so the formatting panel, the preview's
block editor, and the AI's edit proposals all share one undo history and
one save path.

# The formatting panel

[FormattingSidebar](/views/formatting-sidebar.md) is a left pane toggled
from the toolbar (`sidebar.left`, ⌘⌥F). It is a dumb view: it emits a
`FormatCommand`, and `DocumentView.applyFormatCommand` maps that onto
[MarkdownFormatter](/components/markdown-formatter.md) and writes the
result.

The range a command applies to depends on the mode. In Source mode it is
the live `NSTextView` selection. In Preview mode the web view reports the
selected *string*, which
[SourceSelectionResolver](/components/markdown-formatter.md) maps back to
a source range.

That mapping is the whole reason formatting worked at all in Preview. The
preview reports **rendered** text while commands edit **Markdown source**,
so a plain substring search fails for anything carrying formatting —
`Date: 2026` is nowhere to be found in `**Date:** 2026`. The resolver
matches against a normalised projection of the source (Markdown
punctuation dropped, whitespace collapsed) while keeping an index map back
to real offsets, so the returned range lands on the text itself and
excludes the surrounding markers.

A selection that still cannot be located is reported to the user rather
than silently becoming offset 0 — applying the command to the top of the
document while the user watched their selection is what made the panel
look like it did nothing. Commands that
rewrite text (the Persian tools) fall back to the whole document when
nothing is selected; `pinDirection` requires a selection, since wrapping
the entire file in direction marks is never what was meant.

# Editing a block in the preview

Double-clicking a rendered block swaps it for a `textarea` holding **that
block's Markdown source**, and committing splices just that range back
into the document.

This is deliberately not WYSIWYG. Converting rendered HTML back to
Markdown would reformat the whole file on every edit — losing the
author's spacing, their choice of `*` vs `_`, reference links, and
anything Markdown expresses in more than one way. Editing the source of
one block and splicing by range leaves every byte outside that block
untouched.

It works because `renderMarkdown` renders **token by token** rather than
in one pass: `marked.lexer` gives each top-level token a `raw` string,
and those raws concatenate back to the source exactly, so each rendered
block can record `data-mv-start` / `data-mv-length`. Those four
properties — raws round-trip, each slice equals its token's raw,
splicing preserves the prefix and suffix, and per-token rendering matches
whole-document rendering — are what the feature rests on.

The textarea carries `dir="auto"`, so a Persian block edits right-to-left
without any setting. Mermaid blocks are excluded: a diagram has no
meaningful text form to edit in place.

`applyBlockEdit` re-validates the incoming range against the current
document before writing, because the file can change underneath the
preview (a reload from disk, an applied AI edit) between render and
commit.

# Block chrome in the preview

Each rendered block carries two affordances, both revealed only on hover so
the page still reads as a document:

- **Copy and delete**, as icon buttons. Copy opens a small menu offering
  the two forms the same block can take: *as text* (the rendered prose,
  chrome stripped, whitespace runs collapsed) or *as Markdown* (the
  verbatim source slice). Both post to Swift and are written with
  `NSPasteboard` rather than the web clipboard API, which needs a user
  gesture WKWebView doesn't reliably supply. Delete cuts the block's own
  source range, which includes its trailing blank line, so removing a
  block never leaves a hole behind.
- **An insertion point in every gap**, including before the first block
  and after the last. Hovering a gap expands it into a line with an
  "Add block" pill — a labelled pill rather than a bare circle, and the
  `+` is an SVG so it is centred by geometry instead of by a glyph's
  optical metrics;
  choosing a block type from the menu splices a template in at that exact
  source offset, with the blank lines Markdown needs on each side, and the
  new block opens for editing immediately — `pendingEditStart` survives
  the round-trip through Swift and is picked up by the next render.

# The empty document

A new file used to open as a blank preview with no blocks, so there was
nothing to double-click and no sign of how to begin.
[DocumentStarterView](/views/document-starter.md) replaces that with a
set of templates — each of which lands real, clickable blocks — and states
the four things worth knowing about the editing surface.

The hover outline is held off the text by padding that an equal negative
margin cancels, so gaining an outline never shifts the layout. All three
floating surfaces — the copy menu, the insert menu, and the selection bar
— clamp against a guarded viewport size, so a web view that reports a
zero-sized viewport cannot push them off-screen.
