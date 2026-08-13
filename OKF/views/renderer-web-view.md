---
type: View
title: RendererWebView
description: NSViewRepresentable wrapper around a WKWebView that hosts the marked.js/mermaid.js-rendered Markdown preview.
resource: MarkView/Views/RendererWebView.swift
tags: [view, webview, preview]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Wraps a `WKWebView` loading the bundled
`MarkView/Resources/renderer.html`, and attaches it to
[DocumentNavigator](../components/document-navigator.md) via
`attachPreview(_:)` so `PreviewBridge` can drive it. See
[rendering-pipeline](../architecture/rendering-pipeline.md) for how
Markdown text reaches the page and how Mermaid diagrams are rendered
inside it.

Fenced code blocks are highlighted locally after Markdown and Mermaid rendering,
using a lightweight language-aware tokenizer and an adaptive semantic palette for
keywords, strings, numbers, types, functions, comments, and operators. No remote
assets or network request are needed, and the fence language appears as a quiet
label within the code surface.

Document text updates are pushed into the page's JS **only when the
rendered inputs actually changed** (content, file extension, or
appearance) — the coordinator remembers what it last rendered, because a
re-render wipes the selection and scroll position. Zoom is applied as its
own call for the same reason.

The reverse direction (page → Swift) does not carry edits — the preview
is read-only, all edits happen in the source view — but it does carry
`onTextSelected` (non-empty selections only) and `onSelectionAction`,
which delivers a `PreviewSelectionRequest` when the floating bar over a
selection is used.
