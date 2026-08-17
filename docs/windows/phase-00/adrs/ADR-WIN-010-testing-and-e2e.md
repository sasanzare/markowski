# ADR-WIN-010: Test pyramid and native Tauri E2E

- Status: Proposed
- Date: 2026-08-16
- Scope: Validation architecture

## Context

The current repository has a substantial Swift test corpus but cannot run on
this Windows host. Browser-only checks cannot prove Tauri IPC, WebView2,
Credential Manager, file watching, or installer behavior.

## Decision

Use pure Rust unit tests, temporary-files integration tests, renderer/browser
goldens, native Windows Tauri WebDriver E2E, and a macOS regression lane for
shared contracts. Report `NOT RUN` or `BLOCKED` explicitly.

## Alternatives and why rejected

- Manual testing only: rejected for document safety and provider races.
- Browser tests only: rejected because native boundaries are untested.
- Windows tests only: rejected because shared behavior can regress macOS.

## Consequences

CI becomes multi-lane and requires a Windows runner. Native tests are slower but
provide the evidence required for release.

## Security

E2E must include hostile renderer content, forged messages, secret-store
failure, redaction, and path traversal scenarios.

## Testing

The exact pyramid and Tauri WebDriver route are in
`WINDOWS_TEST_STRATEGY.md`; no native run is claimed in Phase 0.

## Cross-platform

Shared fixtures and contract tests run in both lanes; platform-specific behavior
has explicit adapters and matrices.

## Open questions

Choose embedded versus native `tauri-driver` provider for CI, and define test
credential/network fakes without storing live keys.
