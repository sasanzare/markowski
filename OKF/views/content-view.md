---
type: View
title: ContentView
description: Root view for a document window; always presents DocumentView, whether or not the document has content yet.
resource: MarkView/Views/ContentView.swift
tags: [view, root]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`ContentView` takes a `@Binding var document: MarkViewDocument` and the
optional `fileURL` from the `DocumentGroup` scene, and presents
[DocumentView](document-view.md) with the window's `navigationTitle` set
to the file's last path component. On appearance it also registers the
URL with `NSDocumentController`, keeping the welcome window's recent-file
list current.

# Creating documents

**File > New Markdown File** (⌘N) uses `DocumentActions` to show a
save panel rooted in Downloads. Markowski creates and opens that file,
so edits are autosaved to a known location immediately rather than being
held in an untitled document.

# Opening files

Opening a file from [WelcomeView](welcome-view.md) or the File menu uses
an `NSOpenPanel` restricted to `MarkViewDocument.readableContentTypes`,
then routes through `NSDocumentController`. Opening a file always creates
its own document window, consistent with the `FileDocument` architecture.
