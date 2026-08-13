---
type: Swift Type
title: DocumentIndex
description: Splits Markdown source into heading/blank-line-delimited blocks with stable ids, and resolves a DocumentLocation to a block.
resource: MarkView/Models/DocumentIndex.swift
tags: [component, navigation, indexing]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`buildIndex(from:)` walks the document line by line and produces
`DocumentBlock` values (`id: "block-N"`, a `ClosedRange<Int>` of lines,
an optional `headingTitle`, and the block's raw text), splitting on
headings (`#`-prefixed lines start a new block) and blank lines. It also
collects a flat `headings` list.

# Resolving a location

`resolveLocation(_:)` takes a `DocumentLocation` (see
[DocumentLocation.swift](../architecture/navigation-search.md)) and tries,
in priority order:

1. Exact `blockId` match.
2. Case-insensitive substring match against `headingTitle`.
3. The quote, matched through `quoteCandidates(for:)` — the quote as
   given, then its first line, then with Markdown emphasis stripped,
   then its first 40 characters — and, failing all of those, against
   `normalizedForMatching` forms of both sides (emphasis removed,
   whitespace collapsed, lowercased).
4. Line-range containment against `startLine`.

Step 3 is loose on purpose. A model quotes what it *read*, so
`Run npm install first` has to find a source line of
`Run **npm install** first`; an exact substring test silently failed and
"Show in Document" appeared to do nothing.

Returns `nil` if none match, which callers (see
[DocumentNavigator](document-navigator.md)) treat as "nothing to
navigate to" rather than an error.

# Why block ids are regenerated, not persisted

`block-N` ids are assigned by re-running `buildIndex` on every text
change, not stored anywhere. This is why `resolveLocation` falls back
through heading/quote/line-range: a `blockId` from a few edits ago may no
longer point at the same block, but a heading or quoted sentence usually
still identifies the right one.

**These ids are not the renderer's ids.** `DocumentIndex` numbers blocks
over *source* paragraphs while `renderer.html`'s `assignBlockIds` numbers
them over *rendered* DOM children, so the two `block-N` spaces disagree.
Only an ID the renderer itself produced may be passed to
`scrollToBlock`; everything else navigates by text. The AI is never asked
for a `blockId` at all — see
[the AI assistant architecture](/architecture/ai-assistant.md).
