---
type: Architecture
title: Rendering pipeline
description: How Markdown source becomes the live preview shown in a WKWebView, including Mermaid diagrams.
resource: MarkView/Views/RendererWebView.swift
tags: [architecture, rendering, webview, mermaid]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Flow

Rendering happens client-side inside a `WKWebView`, not in Swift:

1. `MarkView/Resources/renderer.html` loads `marked.min.js` and
   `mermaid.min.js` (both vendored, no network fetch) along with
   `renderer.css`.
2. The Swift side (`RendererWebView`) pushes the current document text
   into the page and lets `marked.js` convert it to HTML; fenced code
   blocks with a `mermaid` language tag are handed to `mermaid.min.js`
   for diagram rendering.
3. [DocumentSafetyService.validateMermaidSyntax](/components/document-safety-service.md)
   does a cheap Swift-side pre-check (known diagram-type keywords like
   `graph`, `flowchart`, `sequenceDiagram`) before content reaches the
   WebView, so obviously-invalid Mermaid can surface a clear error
   instead of a silent renderer failure.

# Preview ↔ Swift bridge

`PreviewBridge` (in `DocumentNavigator.swift`) is the one-way channel
from Swift into the page's JavaScript: it evaluates small JS calls like
`scrollToBlock(...)`, `highlightSearchMatches(...)`, and `findText(...)`.
See [navigation-search](navigation-search.md) for how those calls are
driven.

Back the other way, the page posts to the `markview` message handler:
`switchToSource`, `selectionChanged`, and `selectionAction` (the floating
bar over a selection — Ask / Explain / Improve — which becomes a
`PreviewSelectionRequest`).

# Re-render only when the render inputs changed

`renderDocument` replaces `#content.innerHTML` wholesale, which destroys
the user's text selection and scroll position. SwiftUI calls
`updateNSView` on every re-evaluation of the parent view — *including*
the one caused by recording that very selection — so
`RendererWebView.performRender` compares content, file extension, and
appearance against what the coordinator last rendered and does nothing
when they match. Zoom is applied separately, as its own `setZoom` call,
so changing it never rebuilds the DOM.

Skipping this guard doesn't merely waste work: it makes a preview
selection impossible to keep, because making one re-renders the page out
from under it.

# Selection is reported, collapse is not

The page posts `selectionChanged` only for a real, non-empty selection
inside `#content`. It deliberately stays silent when the selection
collapses — clicking into the chat does that — so the composer's pinned
context survives. The floating bar still hides, so nothing on screen
claims a selection that is gone. See
[AIAssistantSidebar](/views/ai-assistant-sidebar.md) for the pinned
context it feeds.

The bar is re-parented to `<html>` on load, because `setZoom` scales
`<body>` and would otherwise scale the bar and corrupt the viewport
coordinates it positions itself with. It anchors above the selection's
first line box, falling back to below the last one, rather than to the
full bounding rectangle — which for a selection spanning many lines
would place it hundreds of pixels away from the text.

# Mermaid as a first-class document type

`.mmd` files are a distinct `UTType` (`org.mermaid.diagram`), readable
directly by `MarkViewDocument`, not just as fenced blocks inside a
regular Markdown file. `TestDocuments/` at the repo root has worked
examples: `flowchart.mmd`, `sequence.mmd`, and a deliberately
`invalid.mmd` for exercising the validation path.
