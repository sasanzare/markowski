# ADR-WIN-007: Typed document safety and persistence

- Status: Proposed
- Date: 2026-08-16
- Scope: Files, autosave, conflicts, and local persistence

## Context

The macOS app relies on `DocumentGroup` autosave and a debounced file watcher.
Windows needs equivalent behavior plus explicit handling for file identity,
revisions, rename/delete, permission errors, and crash-safe writes.

## Decision

Use a Rust document coordinator with separate in-memory, persisted, and on-disk
snapshots. Save through same-directory temporary files, flush/close, atomic
replacement, verification, and a watcher self-write token. All reads and writes
return typed outcomes; read failure is a conflict/unknown state.

## Alternatives and why rejected

- Direct binding writes from the UI: rejected because it cannot coordinate
  external edits or stale proposals safely.
- Timestamp-only conflict checks: rejected because clocks and metadata can lie.
- Always overwrite disk: rejected because it loses user edits.

## Consequences

The coordinator is more explicit than `DocumentGroup`, but can support consistent
undo, AI base checks, recovery, and watcher behavior.

## Security

Path scope, canonicalization, ACLs, reparse-point policy, atomic replacement,
and no content-rich logs are mandatory.

## Testing

Use temp directories, fault injection, concurrent writers, file identity changes,
read-only paths, long paths, and recovery fixtures.

## Cross-platform

The domain protocol is platform-neutral; Windows watcher/replace details stay in
`platform-windows`.

## Open questions

Select backup retention, rename identity semantics, and whether a journal is
needed for very large documents.
