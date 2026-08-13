---
type: Swift Type
title: AIDocumentOperations
description: Decodes the assistant's proposed changes into validated DocumentOperations addressed by short block handles.
resource: MarkView/Services/AI/AIDocumentOperations.swift
tags: [component, ai, editing, document]
status: stable
generated: { by: claude-code/opus-5, at: 2026-08-13T00:00:00Z }
---

# Handles, not UUIDs

`AIBlockHandles` labels a document's blocks `b1`, `b2`, `b3`. The prompt
lists each block under its handle, and the assistant addresses changes by
those. A `UUID` would be the wrong thing to ask a model to copy — long, easy
to corrupt, and a single wrong character means the operation lands nowhere.

# Decoding is validation

`decode` refuses anything that cannot land, naming what went wrong:

- `unknownHandle` — the assistant referred to a block that isn't there.
- `unknownOperation` — it asked for something the document can't do.
- `missingField` — the operation was incomplete.
- `empty` — no changes were proposed at all.

Operation names accept a few aliases (`replace`, `rewriteBlock`, `addRow`)
because models paraphrase. Field values accept an `Int` or a numeric
`String` for the same reason.

An empty document has an explicit prompt marker rather than zero invisible
handles. Its first content is an `insertBlock` with no `after` field. The
operation's Markdown may contain an entire multi-block document; decoding
expands it into ordered insertions and preserves every parsed block instead
of silently keeping only the first one. `createDocument` and `setDocument`
are accepted as empty-document aliases only, so they cannot overwrite a
non-empty file.

Because [RichDocument.applying](markdown-formatter.md) is all-or-nothing over
a batch, a partly-applied assistant edit cannot exist: either every operation
lands or the document is untouched.

# Describing the change

`describe` turns each operation into one sentence in the user's terms —
"Rewrite paragraph “One sentence about…”", "Delete heading 2 “Installation”",
"Add a row to table". The proposal carries these, so the review can say what
is about to change before showing a single character of diff. That is the
practical payoff of a scoped edit over a regenerated file.
