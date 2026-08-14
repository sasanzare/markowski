---
type: Architecture
title: Navigation and search
description: How source and preview stay in sync, and how in-document search matches are found and highlighted in both views.
resource: MarkView/Services/Navigation/DocumentNavigator.swift
tags: [architecture, navigation, search]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Block indexing

[DocumentIndex](/components/document-index.md) parses the document text
into `DocumentBlock`s split on blank lines and headings, each with a
stable `block-N` id, a line range, and an optional heading title. This is
the single source of truth both views resolve locations against.

# Resolving a location

A `DocumentLocation` (from an AI response, a search hit, or a table of
contents click) is resolved to a block by
[DocumentIndex.resolveLocation](/components/document-index.md), trying,
in order: exact `blockId`, heading text match, quoted-text match (loose —
it retries on the quote's first line, on an emphasis-stripped form, and
on a 40-character prefix), then line-range containment. This fallback
order matters because AI-produced locations only ever have a heading, a
quote, or a line range: the AI is never given a `blockId`, and the index's
`block-N` space is not the renderer's anyway (see
[DocumentIndex](/components/document-index.md)).

# Driving the two views

[DocumentNavigator](/components/document-navigator.md) is the
`@MainActor` `ObservableObject` that owns the index, the search state,
and weak references to both the source `NSTextView` and the preview
`WKWebView`. `navigateToLocation` dispatches to whichever view is active:
scroll the WebView via `PreviewBridge.find` (quote, then heading, then
the block's first line) or `.scrollToBlock` — the latter only for an ID
the renderer itself produced — or scroll the source view by counting
lines directly with `enumerateSubstrings(options: .byLines)`.

`findText` in the renderer retries a failed match on looser candidates
(Markdown syntax stripped, first line only, a shortened prefix, the first
few words) because it is matching a quote against *rendered* text; the
exact string often isn't present even when the reference is right.
Preview navigation also tries the reference quote, heading, and resolved block
in sequence rather than treating the first field as authoritative. This is
required for Mermaid references: source tokens such as `sequenceDiagram`
disappear after SVG rendering, but the section heading remains searchable.

# Search

`performSearch` builds an `NSRegularExpression` over the raw text (query
is escaped, so it is literal substring search, not regex search),
producing `SearchMatch` values with line number and range. Matches are
pushed to the preview via `highlightSearchMatches`/`setCurrentSearchMatch`
and to the source view via `NSTextView.setSelectedRange` +
`showFindIndicator`, so `next`/`previousMatch` move both views together.
The find UI itself is [FindBarView](/views/find-bar-view.md).
