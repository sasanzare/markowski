---
type: View
title: RichTextCanvas
description: The WYSIWYG editing surface — an NSTextView on TextKit 2 editing the document directly, with Markdown only as its saved form.
resource: MarkView/Views/Editing/Canvas/RichTextCanvas.swift
tags: [view, editing, canvas, textkit]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-13T00:00:00Z }
---

# What it does

Presents the document as something to edit, not something to look at. It is a
real `NSTextView` created with `usingTextLayoutManager: true`, which is what
opts into TextKit 2 — the older initialiser falls back to TextKit 1 silently,
so there is a test asserting `textLayoutManager` is non-nil.

Being a real text view is the point: the macOS caret, selection, undo, IME,
drag-select, copy/paste, spell checking, the find bar, accessibility, and
bidirectional text all come for free and all behave the way every other Mac
app behaves.

# How it stays in sync

`@Binding var markdown` is the document. On load, and on any change from
*outside*, the binding is parsed and projected into the text storage. On
typing, the storage is read back into a `RichDocument` and serialised.

The coordinator remembers the last Markdown it produced. `updateNSView`
re-projects only when the binding differs from that — so the canvas never
rebuilds itself in response to its own edit, and the caret never jumps.

# Behaviours a document editor needs

- **Readable measure.** The text container is capped and centred like a page
  rather than run to the window edge.
- **Tab in a table** moves to the next cell; inserting a tab there would
  silently create a column.
- **Chrome is protected.** Bullets, checkboxes, and cell separators carry
  `.mvDecoration`; `shouldChangeTextIn` refuses edits that would break them.
- **⌘B and the font panel** go through `changeFont(_:)`, which brings
  `.mvInlineStyle` back into agreement with the new font traits, so a style
  change that looks right also saves right.

See [the document architecture](../architecture/document-architecture.md) for
the projection itself and why presentation and meaning are separate channels.
