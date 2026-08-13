---
type: View
title: DocumentView
description: The main editing surface — source/preview split, the inspector, find bar, and reaction to external file changes.
resource: MarkView/Views/DocumentView.swift
tags: [view, document, editor]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`DocumentView` composes the source editor ([SourceView](../MarkView/Views/SourceView.swift)),
the rendered preview ([RendererWebView](renderer-web-view.md)), the
[InspectorView](../MarkView/Views/InspectorView.swift) (document
metadata from [DocumentLoader](../components/document-loader.md)), and
the [FindBarView](find-bar-view.md), wired to a shared
[DocumentNavigator](../components/document-navigator.md).

It owns a [FileWatcher](../components/file-watcher.md) for the open
`fileURL` and reacts to `fileDidChange` to prompt the user about
external edits, and uses
[DocumentSafetyService](../components/document-safety-service.md) around
saves triggered from the AI edit-apply flow (see
[ai-assistant](../architecture/ai-assistant.md)).

Empty-document onboarding no longer occupies the document canvas. App
launch is handled by the separate [WelcomeView](welcome-view.md), while
every document window is reserved for the actual editor and assistant.

# View modes

Source and preview are togglable/splittable (see `ViewMode`, referenced
by [DocumentNavigator.navigateToLocation](../components/document-navigator.md)),
so a navigation or search action knows whether to scroll the source
`NSTextView` or the preview `WKWebView`.

The `Preview | Editor | Source` switcher sits in the toolbar's centered principal
placement as a compact neutral capsule with text-only options. Its selection
indicator deliberately avoids the app accent color, uses a spring animation,
and reduces motion with the system accessibility setting; it never covers
rendered content or source text.
The indicator is one persistent capsule that slides between the three fixed
segments, so toolbar reconstruction cannot interrupt or remove the transition.

The source mode uses an editable monospaced `NSTextView` bound directly to the document text, with an IDE-style Markdown palette: headings, punctuation, emphasis, code, links, quotes, lists, and HTML each use a stable semantic color role. Edits update the document binding and rendered preview immediately, preserve the native text-view undo stack, and re-highlight without moving the caret. The line-number gutter shares the same light/dark palette and highlights the selected line. Opening the Markowski inspector animates both the resize handle and sidebar from the trailing edge with a spring. The resize target has no permanent divider; hovering or dragging its wider hit area reveals a compact white pill, and dragging persists the new inspector width.

The window uses an AppKit `underWindowBackground` visual effect behind the titlebar and the small gaps between panes, preserving desktop tinting where it communicates window depth. Text-heavy content is deliberately not transparent: the document and Markowski inspector share the same opaque adaptive surface (`#1C1C1C` in dark appearance), so wallpaper color and luminance cannot reduce legibility. The independent rounded panes retain a small breathing gap, adaptive hairline borders, and restrained shadows. Preview CSS paints the full viewport and constrains only `#content`, preventing the centered reading column from leaving dark strips around short or narrow documents. The trailing toolbar action uses a native AI sparkle while the branded character lives in the centered inspector header. The renderer preserves explicit numeric markers on ordered-list items, including descending sequences such as `3, 2, 1`, instead of allowing HTML's sequential numbering to reinterpret the source.
