---
type: Swift Type
title: DocumentLoader
description: Loads file text with security-scoped resource access and computes display metadata (size, counts, modification date).
resource: MarkView/Services/DocumentLoader.swift
tags: [component, document, metadata]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`DocumentLoader` is a stateless `enum` namespace with two entry points:

- `loadString(from:)`: reads a file's contents as UTF-8, wrapping the
  read in `startAccessingSecurityScopedResource()`/
  `stopAccessingSecurityScopedResource()` so it works with URLs granted
  through the sandbox (e.g. from an `NSOpenPanel` or a security-scoped
  bookmark).
- `getMetadata(for:text:)`: returns a `DocumentMetadata` struct (file
  name/extension, formatted and raw byte size, modification date,
  line/word/character counts, path) computed from a combination of
  filesystem attributes (for a real file) and the in-memory `text` (for
  an unsaved/untitled document, size falls back to the UTF-8 byte count
  of `text`).

# Why metadata is separate from loading

`getMetadata` is called far more often than `loadString` — every time
the [InspectorView](/views/document-view.md) needs to refresh counts as
the user types — so it is a pure, cheap function over already-in-memory
text plus a best-effort filesystem stat, not a full re-read of the file.
