---
type: Rust Component
title: Windows document lifecycle domain
description: Platform-neutral document state, content policy, revision tracking, and filesystem-independent save coordination for Windows.
resource: windows/crates/markowski-document/src/lib.rs
tags: [component, windows, rust, document, state-machine, sha256]
status: active
---

# Responsibilities

`markowski-document` validates absolute Markdown/Mermaid paths, decodes
UTF-8/BOM content, normalizes newlines in memory, computes SHA-256 hashes, and
models `Untitled`, `Saved`, `Dirty`, `Saving`, external-change, conflict,
missing, rename, and save-error states.

`DocumentSession` binds a pending save to a memory generation and expected disk
snapshot. `DocumentCoordinator` delegates actual reads and atomic writes to a
`DocumentFileSystem` implementation, so the domain crate has no Win32, Tauri,
WebView, or direct filesystem authority.

# Safety contract

The coordinator refuses ordinary Save from a conflict, missing, or externally
renamed state. A stale disk hash becomes a typed conflict. Reload replaces
memory only through an explicit command. Save completion compares the captured
memory generation so edits made during a write remain dirty.

See [Windows document lifecycle architecture](../architecture/windows-document-lifecycle.md)
and [the phase implementation](../../docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md).
