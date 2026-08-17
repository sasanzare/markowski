# ADR-WIN-003: Same-repository Windows boundary

- Status: Accepted for planning
- Date: 2026-08-16
- Scope: Repository strategy

## Context

The product has an established macOS source tree, OKF bundle, fixtures, and
release documentation. The master plan explicitly calls for a same-repository
Windows implementation while preserving the macOS target.

## Decision

Keep Windows work in this repository under a clearly separated future
`windows/` workspace, with shared fixtures/docs/assets referenced deliberately.
Do not mix Rust/Tauri files into the Swift target and do not duplicate the
authoritative OKF bundle.

## Alternatives and why rejected

- Separate repository: rejected for now because parity fixtures, release notes,
  and cross-platform regression ownership would drift.
- Put Windows files beside Swift services: rejected because build systems and
  platform boundaries would become ambiguous.

## Consequences

One PR can affect both platforms, so CI must run macOS regression checks for
shared contracts. Reviewers need clear path ownership.

## Security

No platform-specific credentials, generated binaries, or local evidence are
committed. `.artifacts/` is ignored for disposable evidence.

## Testing

Separate Rust/frontend/native lanes coexist with the existing Xcode lane.

## Cross-platform

Shared Markdown fixtures and parity IDs are the intended linkage; source code is
not assumed to be portable.

## Open questions

Choose the final workspace directory and CI ownership after the feasibility
spike, without creating production structure in Phase 0.
