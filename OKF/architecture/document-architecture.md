---
type: Architecture
title: Document architecture
description: The block document model as the source of truth, with Markdown as a storage format — and the staged migration away from parse-and-render.
resource: MarkView/Models/Document/RichDocumentModel.swift
tags: [architecture, document, markdown, editing]
status: in-progress
generated: { by: claude-code/opus-5, at: 2026-08-13T00:00:00Z }
---

# The inversion

The app began as `Markdown source → parse → render preview`: the string was
the truth and the canvas was a picture of it. Every edit re-entered a second
representation, and every change re-derived the view. That is a Markdown
editor with a preview, not a document editor.

The target is the other way round:

```
RichDocument (source of truth)
      ↕
NSTextView / TextKit 2
      ↕
Markdown serializer
      ↓
.md file
```

A heading is not `## Title` waiting to be rendered — it is a block whose
`content` is `.heading(level: 2, …)`, carrying its own typography. `**x**`
is not text — it is an `InlineRun` with `.bold` in its `style`. Markdown is
produced on save and consumed on open, nowhere else.

# What is built

**Stage 1 — the model and its storage format.** Done.

- [RichDocumentModel](/components/rich-document.md) — blocks, inline runs
  with styles and links, real table objects, and stable per-block identity.
- `MarkdownDocumentParser` / `MarkdownDocumentSerializer` — the only two
  places Markdown exists.
- [DocumentOperation](/components/document-operation.md) — the addressable
  change both the editor and the assistant speak.

The model refuses to hold states Markdown cannot express, because such a
state is silently destroyed on save. `normalized()` merges adjacent lists of
the same kind (Markdown cannot keep them apart), pads ragged table rows, and
clamps heading levels.

**Stage 2 — the canvas.** Done, and now the Preview surface.

[RichTextCanvas](/views/rich-text-canvas.md) is an `NSTextView` on TextKit 2.
Block structure lives in *attributes* — `.mvParagraph` carries a
`ParagraphDescriptor` (block id, role, line index) — so a heading is a
paragraph with heading typography, never `## `. Reading the storage back
reconstructs the model exactly, which is what makes the text view the live
editing surface rather than a view of one.

Two channels, deliberately kept apart:

- **Fonts are presentation.** A heading and a table header are drawn bold
  because of what they are.
- **`.mvInlineStyle` is meaning.** Inferring style from font traits read that
  typography back as content and turned every heading into `**Heading**`.
  `changeFont(_:)` is overridden so ⌘B still updates both.

Typing mutates `NSTextStorage` directly. `updateNSView` re-projects *only*
when the Markdown changed outside the canvas, compared against the last value
the canvas itself produced — otherwise every keystroke would rebuild the
storage and reset the caret, which is the churn this whole architecture
exists to remove.

Generated chrome (bullets, checkboxes, cell separators) is tagged
`.mvDecoration`: reading strips it, and `shouldChangeTextIn` refuses edits
that would break it. Tab inside a table moves between cells instead of
inserting a character.

Each paragraph resolves its own writing direction from its own text, so a
Persian paragraph in an English document lays out right-to-left with the
bundled font and no setting.

The three modes are now explicit rather than a hidden toggle:

| Mode | What it is |
| --- | --- |
| **Preview** | The original rendered WebView — read-only, Mermaid and all |
| **Editor** | The WYSIWYG canvas: the document as something to edit |
| **Source** | Raw Markdown |

Editor is the default and the mode is remembered. A Mermaid document has no
block model, so choosing Editor for one falls back to Preview rather than
showing an empty canvas — `ViewMode.effective(stored:fileExtension:)`.

**Stage 3 — tables as objects.** Done.

A table is a single `NSTextAttachment` in the storage, backed by
[DocumentTableView](/views/document-table-view.md) — a real grid where each
cell is its own text view. Reading a table out of the canvas is a read of the
attachment's `TableBlock`, not a re-parse of anything, and structural edits
(add or remove a row or column, change an alignment) mutate that model
directly.

Cells are built on an explicit **TextKit 1** stack while the canvas around
them stays on TextKit 2. A bare `NSTextView` gets a TextKit 2 stack where
`textStorage` and `layoutManager` are nil — so cell content silently never
appeared and row heights silently fell back to a constant. A cell is a small,
self-contained run of text; TextKit 1 is the right tool for it.

Column widths are shared out by how much text each column holds, with a
minimum, so a table sizes to its content instead of to fixed tab stops. A
table whose text is Persian lays its columns out right to left.

# What is not built yet

**Stage 4 — the assistant speaks operations.** Done.

"Make this paragraph shorter" now arrives as
`{"op": "replaceBlock", "block": "b2", "markdown": "…"}` — one operation
against one block — instead of a regenerated copy of the file. Nothing
outside the addressed blocks can change, because nothing else is described.

Blocks are addressed by **short handles**, not `UUID`s. A UUID is the wrong
thing to ask a language model to copy: long, easy to corrupt, and one wrong
character means the edit lands nowhere. `AIBlockHandles` labels the document
`b1`, `b2`, `b3`, the prompt shows each block under its handle, and the
mapping back is exact.

`AIDocumentOperations.decode` validates before anything is applied — an
invented handle, an unknown operation, or a missing field is refused with a
sentence naming what went wrong. Batches are all-or-nothing, so a
half-applied assistant edit cannot exist.

The proposal carries a plain-English line per operation ("Rewrite paragraph
“One sentence about…”", "Add a row to table"), so the review says *what* is
changing before showing any diff. `updated_document` is still accepted, so a
model that ignores the operation contract still works.

**Panel ↔ table wiring.** Done, via
[TableSelectionBridge](/components/table-selection-bridge.md). A table lives
in a text attachment, so nothing reading Markdown source can see the caret
inside one — which silently killed the panel's table controls when tables
became objects. The focused cell now reports itself up through the grid, the
attachment, and the canvas; commands travel back down the same path. Source
mode keeps its own `MarkdownFormatter.tableContext` finder and converts into
the same shared shape, so the panel never needs to know which surface it is
driving.

**Stage 5 — applying an edit in place.** A proposal is scoped end to end, but
*applying* it still writes the whole Markdown string, so the canvas
re-projects the entire document. Closing that means applying operations
directly to the canvas's `NSTextStorage`, replacing only the affected block's
range.

The WebView is no longer a fallback — Preview is a mode in its own right, and
the only surface that renders Mermaid.

# Why round-tripping is the gate

Nothing above can ship on a model that loses data. The parser and serializer
are held to: parse → serialize → parse reaches a fixed point, and
serialising again is byte-identical. That is enforced by hand-written cases,
by every document in `TestDocuments/`, by every starter template, and by 300
randomly generated documents per test run.

Three real bugs came out of that property test alone: a code fence shorter
than its own content, checkboxes ignored after an ordered marker, and task
lists modelled as a separate list style when Markdown treats them as
bulleted items carrying a checkbox.

The canvas is held to the same standard one level up: model → attributed →
model must be an identity, across every block kind, inline style, Persian
text, and a realistic document. That test is what caught presentation being
read back as meaning.
