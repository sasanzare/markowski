---
type: Overview
title: MarkView overview
description: A native macOS SwiftUI Markdown viewer/editor with live preview, Mermaid support, and an AI writing assistant.
tags: [markview, overview, swiftui, macos]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it is

MarkView is the source/project name for a document-based macOS app
(`DocumentGroup`) displayed to users as **Markowski**. It opens
`.md` and `.mmd` (Mermaid) files, shows a source editor and a rendered
preview side by side, and lets an AI assistant propose edits to the open
document.

# Stack

- **SwiftUI** app, entry point [MarkViewApp](/components/markview-document.md)
  (`MarkView/App/MarkViewApp.swift`).
- **WKWebView**-hosted preview, rendered client-side with `marked.js` and
  `mermaid.min.js` shipped as bundled resources
  (`MarkView/Resources/*.js`, `renderer.html`, `renderer.css`).
- **AI providers**: Google Gemini, OpenAI, Anthropic, OpenRouter, Mistral,
  Groq, xAI, and DeepSeek, plus a hidden `Mock Provider` for offline
  development, behind a single `AIProvider` protocol.
- API keys live in the macOS Keychain, never in the document or app
  preferences file.

# Top-level source layout

```
MarkView/
  App/           # App entry point and the FileDocument model
  Models/        # Plain data types (document metadata, AI models, navigation)
  Views/         # SwiftUI views, split into AI/, Search/, Settings/ subfolders
  Services/      # Business logic: AI/, Diff/, Navigation/, Safety/, Security/, and file I/O
  Resources/     # marked.min.js, mermaid.min.js, renderer.html/css for the preview WebView
  Commands/      # Menu bar command definitions
```

# Where to go next

- [Document lifecycle](architecture/document-lifecycle.md) — how a file
  becomes an in-memory document, gets saved, and is watched for external
  changes.
- [Rendering pipeline](architecture/rendering-pipeline.md) — how Markdown
  becomes the WKWebView preview.
- [Navigation and search](architecture/navigation-search.md) — how
  source ↔ preview scroll-sync and in-document search work.
- [AI assistant](architecture/ai-assistant.md) — how the assistant talks
  to a provider, proposes edits, and how those edits are reviewed and
  applied.
