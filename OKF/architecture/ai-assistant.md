---
type: Architecture
title: AI assistant
description: How the AI provider abstraction, streaming, and the edit-proposal/diff-review loop fit together.
resource: MarkView/Services/AI/AIService.swift
tags: [architecture, ai, diff]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Provider abstraction

[AIProvider](/components/ai-provider.md) is a small protocol
(`fetchModels`, `streamResponse`, `testConnection`) implemented by
`GeminiProvider`, `OpenAIProvider`, `AnthropicProvider`, the shared
`OpenAICompatibleProvider` used by OpenRouter/Mistral/Groq/xAI/DeepSeek,
and `MockAIProvider` (used for UI development and tests without live API
calls). [AIService](/components/ai-service.md)
is the `@MainActor` owner: it holds the active provider type, the model
list, the conversation, and the current `AIRequestState`.

A request is routed by the *selected model's* provider, not by whichever
provider was toggled last — the model picker is one flat list across
providers, so those two can disagree.

# The response envelope

Every provider is given the same prompt, built once by
`AIPromptBuilder.systemInstruction`, and must answer with one JSON object:

| `type` | Payload |
| --- | --- |
| `chat_response` | `content` (Markdown) |
| `document_reference` | `content`, `location: { heading, quote, startLine, endLine }` |
| `document_operations` | `summary`, `operations` — scoped changes addressed by block handle |
| `document_edit` | `summary`, `updated_document` (legacy; still accepted) |

For an empty file the block listing contains an explicit `EMPTY DOCUMENT`
insertion target. The assistant is instructed to return `insertBlock` with
no `after` handle, and that one operation may carry a complete multi-block
Markdown document. The decoder expands and inserts all blocks in order,
covering first-write requests such as a heading followed by Mermaid and code.

`location.quote` must be verbatim source text: it is what
[DocumentIndex](/components/document-index.md) and the renderer match on.
The schema deliberately has **no `blockId`** — a model cannot know the
renderer's IDs, and when the prompt showed one it was copied literally,
resolving every reference to the top of the document. `AIService` drops
any `blockId` a model sends.

# API keys never touch the document or defaults in plaintext

Each provider has its own stable `keychainAccount` (for example
`gemini_api_key`, `anthropic_api_key`, or `groq_api_key`).
[KeychainService](/components/keychain-service.md)
reads/writes them via macOS Keychain Services, with a base64-in-`UserDefaults`
fallback only when Keychain access itself is unavailable. The
[AISettingsView](/views/ai-settings-view.md) is the only place keys are
entered.

# Model catalog and provider scoping

The sidebar model picker is searchable and combines configured providers in
one vertical list, with each row carrying its provider logo. Every connected
provider's catalog is fetched from its live Models endpoint; Gemini additionally
requires `generateContent` support. Settings exposes that filtered catalog as
searchable checkboxes. `AIModelPreferences` persists an explicit allow-list;
on first connection only up to three recent non-preview models are selected,
while the user can opt into or remove any other text model.
Only checked models from providers with a stored API key reach the composer.
Audio,
realtime, transcription, speech, image, embedding, moderation, and related
non-text families are filtered out. When a provider has no configured key,
its models are omitted from the picker rather than shown as an empty provider.
`MockAIProvider` remains an internal test fixture; its development-only
models are not exposed in the user-facing picker.

Image attachments travel from the composer through `AIService.sendMessage`;
Gemini serializes them as `inline_data`, while OpenAI uses data-URL
`image_url` content parts.

# Request lifecycle

## Token accounting and local limits

Provider streams carry text and, when the API supplies it, an authoritative
input/output token usage event. OpenAI requests `include_usage`; Gemini reads
`usageMetadata`; Anthropic and OpenAI-compatible streams consume usage objects
when those services include them. If a service omits usage, Markowski stores a
clearly marked conservative estimate rather than presenting it as exact.

`AITokenUsageStore` keeps a separate ledger and `AIModelTokenPolicy` for every
model. A model may have no limit or its own numeric cap, with an explicit reset
schedule: Manual keeps the counter until the user presses Reset now, while Daily
resets it automatically at local midnight. Before a request, `AIService`
estimates the complete input (document, selection, recent history, prompt, and
images), blocks an exhausted model, and caps the requested output to the
remaining allowance; after completion it records the provider's real usage.
Settings exposes these controls inline under each model rather than using shared
provider pools. Known reasoning models also expose Low / Medium / High effort;
that selected effort is passed to supported OpenAI-style request APIs.

The usage meter is local to requests sent by this app and key. It does not claim
to represent traffic generated elsewhere; an organization-wide OpenAI usage
view would require separate organization/admin credentials.

`AIRequestState` is the state machine driving the sidebar UI:

```
idle → preparing → thinking → streaming(text) → validating → proposedEdit(proposal)
                                                              ↘ applying → idle
                                                    (or) failed(message) / cancelled
```

Streamed text is parsed incrementally by
`AIService.extractPartialContent` so the [AIAssistantSidebar](/views/ai-assistant-sidebar.md)
can render partial Markdown while a response is still arriving. Prose
that already arrived is committed to the conversation even when the
request ends in `.cancelled` or `.failed`, so stopping a response never
erases what was on screen.

Failures carry the provider's own words: a non-200 becomes an
`AIProviderError.httpStatus` holding the status and the API's `error.message`,
so the sidebar distinguishes a rejected key from a missing model from a
quota trip.

# Edit proposals and diff review

When the assistant's response includes a document rewrite, it becomes an
`AIEditProposal` (`summary`, `updatedDocument`, `originalDocument`, `originalHash`,
`status: pending|applied|discarded|reverted`). `originalHash` is the same
SHA-256 hash produced by
[DocumentSafetyService](/components/document-safety-service.md), so the
app can refuse to apply a proposal computed against a version of the
document that has since changed. [DiffEngine](/components/diff-engine.md)
computes an LCS-based line diff between the current text and
`updatedDocument`, rendered by [DiffReviewSheet](/views/diff-review-sheet.md)
and [AIDiffView](/views/diff-review-sheet.md) before the user accepts or
discards it. The original snapshot remains attached to the committed proposal,
so the latest AI change always exposes both native Undo and deterministic Revert.

# Content blocks, not just chat bubbles

`AIMessage.blocks` is a list of `AIContentBlock` (`markdown`,
`documentReference`, `editProposal`, `status`, `error`) rather than one
flat string, so the sidebar can give a cited document location or a diff
its own UI treatment instead of collapsing everything into prose. Legacy
messages without `blocks` are synthesized on the fly from
`content`/`documentLocation`/`editProposal` (`AIMessage.contentBlocks`).
