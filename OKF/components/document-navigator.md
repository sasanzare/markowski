---
type: Swift Type
title: DocumentNavigator
description: The @MainActor ObservableObject that owns the document index, search state, and drives scroll-sync between source and preview.
resource: MarkView/Services/Navigation/DocumentNavigator.swift
tags: [component, navigation, search]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Holds a [DocumentIndex](document-index.md), the current `searchQuery`
and `searchMatches`, and weak references to the live `WKWebView` and
`NSTextView` so it can drive either without owning them.

Also defines `PreviewBridge`, a small wrapper that turns Swift calls
(`scrollToBlock`, `highlightSearchMatches`, `setCurrentSearchMatch`,
`clearSearch`, `find`) into `evaluateJavaScript` calls against the
renderer page described in
[rendering-pipeline](/architecture/rendering-pipeline.md).

# Key methods

- `updateDocumentText(_:)`: rebuilds the index and, if a search is
  active, re-runs it — called on every document text change.
- `navigateToLocation(_:text:viewMode:reduceMotion:)`: resolves the
  location via the index, then tells the preview to try the quote, heading,
  and resolved block until one is visibly found, or scrolls the source
  `NSTextView` to the resolved line. The candidate fallback keeps Mermaid
  citations navigable after their source has rendered into SVG.
- `performSearch(query:in:)`: builds an escaped, case-insensitive
  `NSRegularExpression` (so search is literal-substring, not
  regex-as-typed), producing `SearchMatch` values with line number and
  `NSRange`; pushes highlight state to both the preview and the source
  view.
- `nextMatch()`/`previousMatch()`: wrap-around cycling through
  `searchMatches`, keeping the source selection, the preview highlight,
  and `selectedMatchIndex` all in sync.

# Deferred source scroll

If `navigateToLocation`/`scrollSourceToLine` fires before the source
`NSTextView` has attached (`sourceTextView` is `nil`), the target line is
stashed in `pendingSourceLine` and applied later via
`sourceViewReady()`, called once the view appears.
