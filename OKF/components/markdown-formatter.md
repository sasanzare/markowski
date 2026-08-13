---
type: Swift Type
title: MarkdownFormatter & PersianTextTools
description: Pure Markdown source transforms behind the formatting panel, plus the Persian text cleanups that Markdown editing in Farsi needs.
resource: MarkView/Services/Editing/MarkdownFormatter.swift
tags: [component, editing, markdown, persian]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-12T00:00:00Z }
---

# Why these are pure functions

Every command takes `(text, NSRange)` and returns a `MarkdownEdit`
(the whole new document plus where the selection should land). Nothing
here touches AppKit or SwiftUI, so the entire surface is unit-testable —
and the same logic serves the source editor, the formatting panel, and
anything that edits Markdown later. `MarkdownEdit` returns the new
selection because a text view otherwise has to re-derive the caret after
every transform, and gets it wrong.

Ranges are UTF-16 (`NSString`), matching `NSTextView.selectedRange()`.

# What it covers

- **Inline spans** — `toggleInline` wraps *or* unwraps, handling both
  `**|bold|**` (markers inside the selection) and `**bold|selected|**`
  (markers outside it). An empty selection leaves the caret between the
  markers.
- **Blocks** — heading levels (which *replace* rather than stack),
  line prefixes (`> `, `- `, `- [ ] `) that toggle across a multi-line
  selection, and ordered lists that renumber. Switching list type strips
  the old marker instead of stacking on it.
- **Insertions** — link, code fence, horizontal rule, table. These go
  through `insertBlock`, which computes the blank line a new Markdown
  block needs before and after it. Without that the inserted table got
  welded onto the end of the previous paragraph and stopped parsing as a
  table.
- **Direction** — Markdown has no alignment syntax, so `setBlockDirection`
  wraps the block in `<div dir="rtl" markdown="1">`. Applying the same
  direction again unwraps, so the control reads as a toggle; the opposite
  direction re-wraps rather than nesting.
- **Tables** — `tableContext(in:at:)` finds the GFM table around a caret
  and returns its rows, alignments, and the caret's row/column. Add and
  delete row/column and per-column alignment all round-trip through
  `render`. The header row is not deletable, since that would stop the
  table being a table.

# PersianTextTools

Cleanups a plain text editor never does, and Persian Markdown always
needs: Arabic letter forms (`ي`, `ك`, `ة`) normalised to their Persian
equivalents, digit conversion in both directions, Persian punctuation
(`،` `؛` `؟`) with correct spacing, and the zero-width non-joiner
(نیم‌فاصله) inserted after `می`/`نمی` and before the common suffixes —
`می رود` → `می‌رود`, `کتاب ها` → `کتاب‌ها`. `fixAll` runs the lot.

`tidyWhitespace` collapses runs of spaces but **preserves Markdown hard
breaks**: two or more trailing spaces are kept, normalised to exactly
two.

`pinDirection` wraps a neutral run (digits, a Latin word) in RLM/LRM
marks so it stops jumping to the wrong side of a Persian line.

# SourceSelectionResolver

`SourceSelectionResolver.range(of:in:)` maps text selected in the rendered
preview back to a range in the Markdown source: exact substring first,
then a normalised projection of the source (Markdown punctuation removed,
whitespace collapsed, line-leading list and quote markers dropped) with an
index map back to real UTF-16 offsets. It returns `nil` rather than a
guess when the selection genuinely isn't there.

The resulting range covers the text and not its markers, which is what
makes a second Bold on an already-bold selection *unwrap* it instead of
nesting another pair.
