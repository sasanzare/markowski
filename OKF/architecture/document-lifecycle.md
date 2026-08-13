---
type: Architecture
title: Document lifecycle
description: How a Markdown file becomes an editable in-memory document, is saved safely, and is watched for external changes.
resource: MarkView/Models/DocumentModel.swift
tags: [architecture, document, filesystem]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Flow

1. **Launch**: Markowski suppresses the automatic untitled document and
   opens a dedicated [WelcomeView](/views/welcome-view.md). It offers a
   new-file action, an open action, and the most recent Markdown files
   reported by `NSDocumentController`.
2. **Create**: **File > New Markdown File** (⌘N) and the welcome
   action present a save panel rooted in the user's Downloads folder.
   The chosen `.md` file is created first and then opened as a normal
   document, so it has a real save location from the first edit.
3. **Open**: [MarkViewDocument](/components/markview-document.md) is a
   `FileDocument` conforming type registered with SwiftUI's
   `DocumentGroup` (`MarkViewApp.swift`). It reads readable content types
   `public.markdown`, `.plainText`, and the custom `org.mermaid.diagram`
   UTType, falling back from UTF-8 to ASCII decoding if needed.
4. **Autosave**: `DocumentGroup` owns autosaving the editable
   `FileDocument` in place. Markdown and Mermaid document declarations
   use the `Editor` role, and newly created files already have their
   final URL, avoiding the ambiguous untitled-save flow.
5. **Metadata**: [DocumentLoader](/components/document-loader.md)
   computes display metadata (size, line/word/character counts,
   modification date) separately from the document's text, using
   security-scoped resource access for sandboxed file reads.
6. **Edit safety**: [DocumentSafetyService](/components/document-safety-service.md)
   hashes the document text (SHA-256) at load time so the app can detect
   whether the file on disk changed underneath an open document, and
   performs atomic writes on save.
7. **External change detection**: [FileWatcher](/components/file-watcher.md)
   uses a `DispatchSourceFileSystemObject` on the file descriptor to
   detect writes, extends, renames, and revokes from outside the app
   (e.g. another editor, `git checkout`), debounced by 250ms, and flips
   `fileDidChange` for the UI to react to.

# Why hashing and watching are separate

`DocumentSafetyService` answers "has this specific content changed since
I loaded it" (a pull, triggered before a save). `FileWatcher` answers "did
something touch this file just now" (a push, from the OS). The AI edit
flow (see [ai-assistant](ai-assistant.md)) uses the hash to make sure a
proposed edit is still being applied against the document it was
generated from.
