---
type: Architecture
title: Windows document lifecycle and filesystem safety
description: The Phase 3 Windows document state machine, typed IPC boundary, atomic persistence, and external-change reconciliation.
resource: docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md
tags: [architecture, windows, document, filesystem, safety, concurrency]
status: active
---

# Purpose

Phase 3 makes Markdown files the authoritative Windows document source while
keeping filesystem authority below the Tauri shell. The lifecycle is divided
into a platform-neutral domain coordinator and a Windows adapter; the Leptos
surface only sends typed commands and renders typed state.

# Flow

1. The native dialog returns an absolute `.md` or `.mmd` path.
2. The Windows adapter performs a stable read and returns bytes plus a file
   fingerprint.
3. The domain decodes UTF-8/BOM, normalizes in-memory newlines, and records a
   SHA-256 disk revision.
4. Edits advance a memory generation and make the document dirty.
5. Save captures a revision-bound proposal, compares the expected disk hash,
   writes a flushed same-directory temporary file, atomically replaces the
   target, and verifies the final hash.
6. A debounced watcher asks the coordinator to reconcile the actual target;
   it does not map raw filesystem events directly to product state.

# Boundaries

- `windows/crates/markowski-document/src/lib.rs` owns typed state, encoding,
  hashes, conflict transitions, and save concurrency semantics.
- `windows/crates/markowski-platform-windows/src/lib.rs` owns Win32 replace,
  native dialogs, stable reads, and `notify`.
- `windows/apps/desktop-shell/src/lib.rs` owns typed Tauri commands, state
  serialization, watcher lifecycle, and close confirmation.
- `windows/apps/desktop-ui/src/app.rs` owns the minimal lifecycle surface,
  debounced edit updates, persisted-path autosave, and visible status.

# Safety invariants

- A stale expected disk revision produces `Conflict`/`DiskConflict`; it cannot
  be silently overwritten.
- A newer in-memory edit remains dirty after an older save completes.
- Dirty external edits become `Conflict`; clean external edits become
  `ExternalChanged` and require explicit reload.
- Delete and untrusted rename preserve memory and require Save As/recovery.
- Untitled documents never autosave to an invented hidden location.
- No generic frontend filesystem, network, shell, process, credential, or
  persistence capability is added.

See the [phase implementation](../../docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md)
and [acceptance matrix](../../docs/windows/phase-03/ACCEPTANCE_MATRIX.md).
