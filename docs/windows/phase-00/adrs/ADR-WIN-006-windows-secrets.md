# ADR-WIN-006: Windows Credential Manager without fallback

- Status: Proposed
- Date: 2026-08-16
- Scope: API key storage

## Context

The macOS service uses Keychain but falls back to Base64 in UserDefaults when a
Keychain operation fails. The Windows invariant requires secure OS storage.

## Decision

Implement a narrow Rust secret-store trait backed by Windows Credential Manager.
If it is unavailable or fails, report an actionable unavailable state and do not
write the secret to ordinary files, registry values, UserDefaults-equivalents,
logs, or chat data.

## Alternatives and why rejected

- DPAPI-encrypted app file: possible future migration aid, but it is still an
  application-managed fallback and is not the first-line store.
- Plain or Base64 app data: rejected; reversible encoding is not protection.
- Environment variables: rejected for persistence and accidental log exposure.

## Consequences

Users may need to re-enter a key when the OS store is unavailable. The adapter
needs a Windows test seam and careful target-name migration.

## Security

Use Credential Manager APIs, minimum necessary access, redacted errors, and no
secret-returning IPC method. Credential storage failure is fail-closed.

## Testing

Put/get/delete, access denial, migration, concurrent use, crash, and negative
ordinary-storage scans must pass on Windows.

## Cross-platform

The trait can map to macOS Keychain later, but Phase 0 does not change the
existing fallback or silently migrate its data.

## Open questions

Define target naming/version migration and whether account labels are provider
IDs only or include profile/environment names.
