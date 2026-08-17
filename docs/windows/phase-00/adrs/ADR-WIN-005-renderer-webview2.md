# ADR-WIN-005: Hardened offline renderer in WebView2

- Status: Proposed
- Date: 2026-08-16
- Scope: Preview and Mermaid rendering

## Context

The macOS renderer uses bundled marked/Mermaid assets in a local WebKit view and
has source-range/block callbacks. The Windows plan selects WebView2, but the
observed HTML has no CSP and Mermaid is configured with `securityLevel: loose`.

## Decision

Use a bundled offline renderer/WebView2 surface for behavioral parity only after
security hardening: strict CSP, no remote scripts, explicit raw-HTML policy,
safe Mermaid configuration, document-root image allowlists, origin checks, and
typed bridge messages.

## Alternatives and why rejected

- Native Markdown control: rejected for Mermaid and feature parity risk.
- Remote web renderer: rejected for offline/local-first behavior and data
  exposure.
- Copy macOS renderer unchanged: rejected because its security configuration is
  not sufficient as a Windows baseline.

## Consequences

Renderer reuse reduces feature work but creates a WebView security/test surface.
Some HTML/Mermaid features may need documented compatibility changes.

## Security

The app origin, CSP, navigation policy, bridge schema, and local asset resolver
are security boundaries. Hostile documents are test inputs.

## Testing

Browser goldens, CSP audits, hostile HTML/image/Mermaid corpus, WebView2 native
E2E, and offline/no-network assertions are required.

## Cross-platform

The behavior corpus can be compared with macOS WebKit; implementation settings
are not assumed identical.

## Open questions

Choose virtual-host/custom-protocol details and define the supported raw HTML
subset after the first WebView2 spike.
