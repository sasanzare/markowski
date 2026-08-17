# ADR-WIN-012: Defer distribution decisions until native evidence

- Status: Proposed
- Date: 2026-08-16
- Scope: Installer, signing, updater, and release evidence

## Context

Tauri supports Windows MSI/NSIS and Evergreen or fixed WebView2 installation
modes, but the repository has no Windows shell, signing setup, or runtime
artifacts. Choosing packaging details now would create false confidence.

## Decision

Phase 0 records requirements and evidence fields only. Phase 1 must first prove a
minimal native shell, then choose installer target, WebView2 mode/minimum
version, code signing, update channel, rollback, and offline/enterprise policy.

## Alternatives and why rejected

- Commit an installer configuration now: rejected because it cannot be tested
  and would be production Phase 1 work.
- Assume system Evergreen runtime everywhere: rejected because offline and
  enterprise environments differ.
- Assume fixed runtime is always safer: rejected because bundle size and patch
  responsibility are material.

## Consequences

The project cannot claim a Windows installer or update path yet. A later spike
must produce evidence before release work is accepted.

## Security

Artifacts must be signed, hashes/manifests published, update signatures checked,
and WebView2 runtime ACL/DLP assumptions documented. No signing secrets belong in
the repository.

## Testing

Clean-machine install/uninstall/upgrade/rollback, offline launch, runtime
absence/incompatibility, and signature verification are release-candidate gates.

## Cross-platform

Windows distribution remains separate from the macOS notarization/release lane;
shared versioning and release notes must not imply Windows availability early.

## Open questions

Select MSI versus NSIS, signing provider, update mechanism, telemetry policy (if
any), and fixed/Evergreen runtime after the native smoke build.
