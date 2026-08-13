---
type: Swift Type
title: DocumentSafetyService
description: SHA-256 content hashing, atomic file saves, and Mermaid syntax pre-validation.
resource: MarkView/Services/Safety/DocumentSafetyService.swift
tags: [component, safety, hashing, mermaid]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Four static functions, each independent:

- `computeHash(text:)`: SHA-256 (via `CryptoKit`) hex digest of the
  document text. Used as the identity of "this exact content" across the
  app — see [ai-assistant](/architecture/ai-assistant.md) for how it
  guards edit proposals.
- `hasFileChangedExternally(fileURL:originalHash:)`: re-reads the file at
  `fileURL` and compares its hash to a previously captured
  `originalHash`. Returns `false` (not changed) if the file can't be
  read, i.e. it fails closed toward "assume unchanged" rather than
  surfacing a spurious conflict.
- `saveDocumentSafely(to:content:)`: writes UTF-8 data with the
  `.atomic` option, so a save can't leave a half-written file if the app
  is interrupted mid-write.
- `validateMermaidSyntax(content:)`: checks the first non-empty,
  non-comment (`%%`) line against a fixed list of known Mermaid diagram
  headers (`graph`, `flowchart`, `sequenceDiagram`, `classDiagram`,
  `stateDiagram`, `erDiagram`, `gantt`, `pie`, `gitGraph`, `mindmap`).
  This is a cheap Swift-side sanity check, not a full Mermaid parser —
  see [rendering-pipeline](/architecture/rendering-pipeline.md).

# Relationship to FileWatcher

`hasFileChangedExternally` is a pull-based, on-demand check (e.g. "was
this changed since I last hashed it, right before I save"), distinct
from [FileWatcher](file-watcher.md)'s push-based OS-level notifications.
