---
type: Swift Type
title: MarkViewDocument
description: The FileDocument conforming type SwiftUI's DocumentGroup uses to open and save a Markdown or Mermaid file.
resource: MarkView/Models/DocumentModel.swift
tags: [component, document, filedocument]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`MarkViewDocument` is a `FileDocument` holding the in-memory `text` and
the originating `fileURL`. It declares three readable content types:
`.markdownDocument` (`public.markdown`), `.plainText`, and the custom
`.mermaidDiagram` UTType (`org.mermaid.diagram`).

# Decoding fallback

`init(configuration:)` tries UTF-8 first; if that fails it retries with
ASCII before throwing `CocoaError(.fileReadInapplicableStringEncoding)`.
This exists because some legacy `.md` files in the wild are not valid
UTF-8.

# Saving

`fileWrapper(configuration:)` writes `text` as UTF-8 `Data`. Note this is
the SwiftUI document-architecture save path; the app-triggered "safe
save" used elsewhere (for example after an AI edit is applied) goes
through [DocumentSafetyService.saveDocumentSafely](document-safety-service.md)
instead, which writes atomically.

# Where it's used

Registered in `MarkViewApp.swift`'s `DocumentGroup(newDocument:)`, it is
created for untitled documents by **File > New Markdown File** (⌘N),
which calls `NSDocumentController.shared.newDocument(nil)`. It is consumed as a
`@Binding` by [ContentView](/views/content-view.md) and
[DocumentView](/views/document-view.md).
