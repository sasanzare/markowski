# Components

One concept per notable Swift type or service. See
[architecture/](../architecture/) for how these fit together.

# Windows

* [windows-shell](windows-shell.md) - The Windows Leptos shell, typed lifecycle bridge, and local-only interaction contract.
* [windows-ui-state](windows-ui-state.md) - Typed session-only mode, theme, fixture, sidebar, and pane state.
* [windows-document-lifecycle](windows-document-lifecycle.md) - Platform-neutral document state, hashes, encoding policy, and save coordination.
* [windows-platform-filesystem](windows-platform-filesystem.md) - Windows stable reads, atomic replacement, native dialogs, and watcher adapter.

# Document I/O

* [markview-document](markview-document.md) - `FileDocument` model backing the app's open/save.
* [document-loader](document-loader.md) - Reads file text and computes display metadata.
* [document-safety-service](document-safety-service.md) - Hashing, atomic saves, and Mermaid pre-validation.
* [file-watcher](file-watcher.md) - Detects external file changes.

# Navigation

* [document-index](document-index.md) - Splits document text into addressable blocks.
* [document-navigator](document-navigator.md) - Drives source/preview scroll-sync and search.

# AI

* [ai-service](ai-service.md) - Owns the AI conversation and request state machine.
* [ai-provider](ai-provider.md) - The protocol implemented by each AI backend.
* [diff-engine](diff-engine.md) - LCS line diff used to review AI edit proposals.

# Security

* [keychain-service](keychain-service.md) - Stores provider API keys in the macOS Keychain.

# Editing

- [MarkdownFormatter & PersianTextTools](markdown-formatter.md) — pure Markdown source transforms behind the formatting panel, and the Persian text cleanups beside them.
- [TableSelectionBridge](table-selection-bridge.md) — connects the formatting panel to the table holding the caret, on either surface.
- [AIDocumentOperations](ai-document-operations.md) — decodes the assistant's changes into validated operations addressed by short block handles.
