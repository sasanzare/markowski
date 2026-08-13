---
type: Swift Type
title: AIProvider
description: The protocol every AI backend implements, keeping AIService backend-agnostic.
resource: MarkView/Services/AI/AIProvider.swift
tags: [component, ai, protocol]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# Contract

```swift
protocol AIProvider {
    var providerType: AIProviderType { get }
    func fetchModels(apiKey: String) async throws -> [AIModel]
    func streamResponse(
        prompt: String,
        documentText: String,
        selectedText: String?,
        documentType: String,
        history: [AIMessage],
        model: AIModel,
        apiKey: String
    ) -> AsyncThrowingStream<String, Error>
    func testConnection(apiKey: String) async throws -> Bool
}
```

# Implementations

- `GeminiProvider` (`Services/AI/Google/GeminiProvider.swift`) — Google
  Gemini.
- `OpenAIProvider` (`Services/AI/OpenAI/OpenAIProvider.swift`) — OpenAI.
- `AnthropicProvider` (`Services/AI/Anthropic/AnthropicProvider.swift`) —
  Anthropic's native Models and Messages APIs.
- `OpenAICompatibleProvider`
  (`Services/AI/OpenAI/OpenAICompatibleProvider.swift`) — the shared adapter
  for OpenRouter, Mistral, Groq, xAI, and DeepSeek.
- `MockAIProvider` (`Services/AI/MockAIProvider.swift`) — deterministic,
  offline responses; used for UI development and tests without live API
  calls or a stored key (`AIProviderType.mock`'s `keychainAccount` is
  `mock_api_key` but the mock provider does not require a real one).

# Shared prompt and error types

`AIProvider.swift` also holds two pieces every implementation needs:

- **`AIPromptBuilder.systemInstruction(documentText:selectedText:documentType:)`**
  builds the single JSON-envelope prompt (`chat_response`,
  `document_reference`, `document_edit`). Providers must not carry their
  own copy — they did, and the two drifted. The response schema is
  documented in [the AI assistant architecture](/architecture/ai-assistant.md).
- **`AIProviderError`** carries the HTTP status *and* the provider's own
  message so the sidebar can say "OpenAI rejected the API key" instead of
  a generic retry prompt. `AIProviderResponse.errorDetail(from:)` pulls
  `{"error": {"message": …}}` out of a body, including Gemini's
  array-wrapped streaming form. A provider that returns a non-200 must
  drain the response body and throw `AIProviderError.httpStatus` rather
  than a bare `URLError`, and must throw
  `AIProviderError.emptyResponse` if the stream yields nothing.

# Why one protocol, not three call sites

[AIService](ai-service.md) routes through the provider that owns the
selected model, so adding a fourth backend (e.g. a local model) means
implementing this protocol and adding one `case` to `AIProviderType`
(see [add-ai-provider playbook](/playbooks/add-ai-provider.md)) — no
changes to the sidebar, the state machine, or the edit-proposal flow.
`streamResponse` returning `AsyncThrowingStream<String, Error>` is the
one shape every provider's SSE/streaming API is adapted into.
