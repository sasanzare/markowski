---
type: Swift Type
title: AIService
description: The @MainActor ObservableObject owning the AI conversation, provider selection, model list, and request state machine.
resource: MarkView/Services/AI/AIService.swift
tags: [component, ai, state-machine]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`AIService` wires together the three [AIProvider](ai-provider.md)
implementations (`GeminiProvider`, `OpenAIProvider`, `MockAIProvider`)
behind `activeProviderType`, and publishes:

- `availableModels` / `selectedModel`, refreshed from `fetchModels`
  whenever the provider changes, persisted per-provider in
  `UserDefaults` (`selectedAIModel_<providerRawValue>`). Gemini is exposed
  through the fixed three-model catalog (`gemini-pro-latest`,
  `gemini-flash-latest`, and `gemini-flash-lite-latest`) after a successful
  connection. OpenAI results are reduced to text-capable model IDs; audio,
  realtime, transcription, speech, image, embedding, moderation, and other
  non-text model families are excluded.
- `conversation: [AIMessage]`.
- `currentState: AIRequestState` — see the state diagram in
  [ai-assistant](/architecture/ai-assistant.md).
- `activeProposal: AIEditProposal?`.

# Model refresh gating

`refreshModels()` short-circuits to an empty model list when the active
provider is not `.mock` and its Keychain-stored API key is empty, so the
UI can distinguish "no key configured" from "key configured but the
provider call failed" (the latter also empties the list, but only after
attempting the network call).

`configuredProviderTypes` exposes only `.mock`, the active provider, and
providers with a stored key. The model picker uses this list to avoid
showing OpenAI or any other unconfigured provider at all.

A refresh never moves the user off a model they picked: if `selectedModel`
still exists in the refreshed catalog it is left alone, and only otherwise
does the per-provider `UserDefaults` value (then the first available model)
decide.

# The selected model picks the provider

The picker lists every configured provider in one flat list, so a
selection can cross providers. `requestProviderType` is
`selectedModel?.provider ?? activeProviderType`, and `sendMessage` routes
through that provider and reads *its* Keychain account. Routing by
`activeProviderType` instead is how a Gemini request could be sent with
an OpenAI key. `missingKeyProvider` reports the provider a request would
use when it has no key, which is what the sidebar gates on.

# Streaming preview

`streamingPreview` extracts a display-ready partial string from the raw
in-flight `.streaming(text:)` state via
`AIService.extractPartialContent`, so [AIAssistantSidebar](/views/ai-assistant-sidebar.md)
can render incremental Markdown instead of raw provider-specific
streaming chunks. It reads `"content"` and — for a `document_edit`, which
has no `content` — `"summary"`. Because the rest of an edit is one huge
`updated_document` string that can't be shown raw,
`streamingProgressNote` tells the sidebar to say the document is being
written instead of leaving a motionless "Thinking…".

# Nothing streamed is thrown away

`commitPartialResponse` appends whatever prose already arrived to the
conversation before entering `.cancelled` or `.failed`, so stopping a
response — or a mid-stream failure — leaves the text the user was
reading in the transcript. The same path salvages a truncated envelope:
a response cut off at the model's output limit is reported as such rather
than discarded as unreadable.

# Local lookups

`localSearchTerm(from:)` answers literal "where …" questions from the
in-memory [DocumentIndex](document-index.md) without a network call. The
rule is deliberately narrow — a prompt merely *containing* "find",
"mention", or "talk about" used to be intercepted, so requests like "find
the typos and fix them" never reached the model. Prompts carrying an
action verb ("should I", "rewrite", "summarize", …) are always sent on.

# In-flight tracking

`isRequestInFlight` is derived from `currentState`
(`true` for `.preparing/.thinking/.streaming/.validating/.applying`),
and `activeTask: Task<Void, Never>?` holds the in-flight streaming task
so a new request or a user-initiated cancel can supersede it.
