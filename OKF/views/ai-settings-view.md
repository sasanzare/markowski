---
type: View
title: AISettingsView
description: The app Settings scene for managing AI providers, privacy, and API keys.
resource: MarkView/Views/Settings/AISettingsView.swift
tags: [view, settings, ai]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Registered as the app's `Settings` scene in `MarkViewApp.swift`. It presents
a two-pane provider-management workspace that follows the main app's rounded,
neutral surface language. A compact rail shows bundled logos and connection
state for Gemini, OpenAI, Anthropic, OpenRouter, Mistral, Groq, xAI, and
DeepSeek; the detail pane provides secure key controls, connection testing,
model-discovery guidance, and privacy information. The sidebar gear and model picker open this scene
through SwiftUI's `openSettings()` action.

For every connected provider, the detail pane loads the current remote model
catalog and presents text-capable models as searchable checkboxes. Enabled
model IDs are persisted in `UserDefaults`; a provider's first refresh selects
only up to three recent non-preview models, after which explicit user choices
survive refreshes. Audio, speech,
image-generation, embedding, moderation, realtime, and related utility models
are filtered before this list is shown.

Each model row can expand into a compact policy editor. Token limit and
reasoning effort occupy the primary control row; reset behavior is separated
into its own full-width schedule bar with an icon, explanatory status,
Manual/Daily segmented control, and a contextual Reset now action. This keeps
the controls aligned at different Settings window widths and makes the reset
semantics visible without mixing them into the numeric limit field.

API keys are written through
[KeychainService](../components/keychain-service.md) — never into
`UserDefaults` in plaintext, and never into the document. Each provider can
be saved, replaced, removed, or tested with
`AIProvider.testConnection(apiKey:)`; saving or removing a key triggers
`AIService.refreshModels()` so the model picker reflects the available
providers. Logos are bundled in `Assets.xcassets`; the page does not load
remote artwork. It also explains that document content remains local unless
the user explicitly sends a request.
