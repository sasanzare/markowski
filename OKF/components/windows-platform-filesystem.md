---
type: Rust Component
title: Windows filesystem and watcher adapter
description: Windows-only stable reads, flushed same-directory replacement, native Markdown dialogs, and debounced filesystem observation.
resource: windows/crates/markowski-platform-windows/src/lib.rs
tags: [component, windows, rust, filesystem, watcher, win32]
status: active
---

# Responsibilities

`WindowsFileSystem` performs metadata/read/metadata stability checks, maps OS
errors to typed document errors, writes a collision-resistant temporary file in
the target directory, flushes it, replaces with `MoveFileExW`, and verifies the
final bytes.

`WindowsWatcherHandle` watches the target's parent directory with `notify`,
coalesces events for 250 ms, and reports only a small typed signal. The shell
then re-reads the actual target and lets the domain state machine decide
whether the result is clean external change, conflict, missing, or rename.

The native open/save dialogs filter `.md`/`.mmd` and return paths through typed
Tauri commands. They do not grant the WebView a generic filesystem scope.

See [Windows document lifecycle architecture](../architecture/windows-document-lifecycle.md)
and [the phase evidence](../../docs/windows/phase-03/EVIDENCE.md).
