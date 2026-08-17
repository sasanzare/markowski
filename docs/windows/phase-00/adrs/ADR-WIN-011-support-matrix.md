# ADR-WIN-011: Windows support target

- Status: Accepted as product target; validation pending
- Date: 2026-08-16
- Scope: Release support

## Context

The master plan identifies Windows 11 x64 as mandatory, Windows 11 ARM64 as a
build/smoke requirement before GA, and Windows 10/32-bit as non-mandatory/out of
scope. The current host’s OS identity is contradictory.

## Decision

Plan and test Windows 11 x64 first. Do not claim support until a clean machine
passes build, install, WebView2, native E2E, and recovery gates. Prove ARM64
before a GA ARM64 claim. Do not promise Windows 10 or 32-bit.

## Alternatives and why rejected

- Support every Windows edition immediately: rejected because it expands
  WebView2, installer, and input matrix without product need.
- Infer support from kernel build alone: rejected because edition/runtime and
  policy conditions matter.

## Consequences

Support messaging is narrower, but release evidence is meaningful. The current
machine remains an environment with unresolved identity, not a support proof.

## Security

Installer/runtime policy, standard-user execution, ACLs, signing, and updater
verification are part of support rather than optional packaging details.

## Testing

Use the matrix in `WINDOWS_SUPPORT_MATRIX.md` and attach reproducible artifacts.

## Cross-platform

The policy does not change macOS support or its existing release process.

## Open questions

Choose exact Windows build floor, Evergreen/fixed WebView2 mode, and ARM64 CI
hardware before Phase 1 completion.
