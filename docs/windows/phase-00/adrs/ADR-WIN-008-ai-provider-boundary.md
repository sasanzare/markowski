# ADR-WIN-008: Typed AI provider registry and proposal protocol

- Status: Proposed
- Date: 2026-08-16
- Scope: AI providers and document operations

## Context

The macOS service routes multiple providers, dynamically discovers models,
streams responses, captures usage, and validates structured document operations.
Provider wire formats differ for models, images, reasoning, and errors.

## Decision

Use a typed provider trait and registry. Providers return bounded stream events
and capabilities; the AI domain creates validated proposals against an immutable
document base. Providers cannot call storage or mutate the live document.

## Alternatives and why rejected

- One generic HTTP implementation: rejected because capability/error/stream
  differences would become hidden conditionals.
- Provider code inside UI: rejected for secret and test coupling.
- Whole-document model output only: rejected because scoped operations and
  review are safer and already part of the product contract.

## Consequences

New providers require adapter tests and capability metadata. The registry is more
verbose but makes model routing and test fakes explicit.

## Security

Only explicit Send transmits context; keys come from the secret trait; streams
are size/time bounded; responses are untrusted; logs are redacted.

## Testing

Fake provider tests cover discovery, SSE/stream events, cancellation, malformed
JSON, usage, image filtering, HTTP errors, and transactional operation failure.

## Cross-platform

The provider/core contract is portable; networking and credential adapters are
injected and not owned by the UI.

## Open questions

Choose the HTTP runtime, retry policy, model catalog cache lifetime, and whether
provider-specific reasoning fields are represented as a capability enum.
