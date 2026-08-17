# Architecture

Each concept here describes one subsystem: the problem it solves, the
components involved, and how data flows between them.

* [document-lifecycle](document-lifecycle.md) - Opening, editing, saving, and watching a file for external changes.
* [rendering-pipeline](rendering-pipeline.md) - Turning Markdown source into the live WKWebView preview.
* [navigation-search](navigation-search.md) - Source/preview scroll-sync, block indexing, and in-document search.
* [ai-assistant](ai-assistant.md) - The AI provider abstraction, streaming responses, and the edit-proposal/diff-review flow.
* [editing](editing.md) - The formatting panel and editing a block directly in the preview.
* [document-architecture](document-architecture.md) - The block document model as source of truth, and the staged migration to it.
* [windows-architecture](windows-architecture.md) - Implemented Phase 1 Windows Rust/Tauri 2/Leptos/WebView2 boundary, typed IPC, and security baseline.
