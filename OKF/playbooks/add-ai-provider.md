---
type: Playbook
title: Add a new AI provider
description: Steps to add a new AI backend behind the existing AIProvider protocol without touching the sidebar or the edit-proposal flow.
tags: [playbook, ai, provider]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Context

See [ai-provider](../components/ai-provider.md) and
[ai-assistant](../architecture/ai-assistant.md) for why this is a clean
extension point: [AIService](../components/ai-service.md) only ever
calls through the `AIProvider` protocol.

# Steps

1. Add a new case to `AIProviderType` (`MarkView/Models/AIModels.swift`)
   with a `rawValue` for display and a unique `keychainAccount` string.
2. Create a new type conforming to `AIProvider`
   (`MarkView/Services/AI/AIProvider.swift`) implementing
   `fetchModels(apiKey:)`, `streamResponse(...)`, and
   `testConnection(apiKey:)`. Follow the shape of `GeminiProvider`,
   `AnthropicProvider`, or—when the service implements OpenAI-compatible
   models/chat-completions endpoints—configure an `OpenAICompatibleProvider`.
   `streamResponse` must
   adapt the provider's own streaming format into
   `AsyncThrowingStream<String, Error>`. Build the prompt with
   `AIPromptBuilder.systemInstruction` rather than writing a new one, and
   on a non-200 drain the body and throw
   `AIProviderError.httpStatus(provider:code:detail:)` with
   `AIProviderResponse.errorDetail(from:)` — a bare `URLError` reaches the
   user as an unhelpful generic message.
3. Instantiate it in `AIService` alongside `geminiProvider`/
   `openAIProvider`/`mockProvider`, and add the corresponding case to the
   `activeProvider` switch.
4. No changes needed to [AIAssistantSidebar](../views/ai-assistant-sidebar.md),
   [AISettingsView](../views/ai-settings-view.md) (it already iterates
   `AIProviderType.allCases`), [DiffReviewSheet](../views/diff-review-sheet.md),
   or [KeychainService](../components/keychain-service.md).
5. Add its bundled logo to `Assets.xcassets` and map it from
   `AIProviderType.assetName`; Settings enumerates provider cases automatically.
6. If the new provider has a genuinely different response shape (for
   example: returns structured edit proposals rather than a plain-text
   stream to be parsed), that parsing belongs in the new provider's
   implementation or in `AIService.extractPartialContent`'s call site —
   not in the `AIProvider` protocol itself, which should stay
   provider-agnostic.
