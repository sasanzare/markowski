---
type: Architecture
title: Windows architecture implementation
description: Phase 1 production Rust, Tauri 2, Leptos, WebView2, typed IPC, logging, and least-privilege security boundary for Windows.
resource: docs/windows/phase-01/PHASE_01_IMPLEMENTATION.md
tags: [architecture, windows, rust, tauri, leptos, webview2, ipc, security]
status: active
---

# Purpose

This concept records the implemented Windows Phase 1 foundation as an
extension of the existing MarkView macOS knowledge bundle. Production Windows
source lives under `windows/`; Windows planning and evidence remain under
`docs/windows/`.

## Contract

The implementation keeps a platform-neutral Rust core below a thin Tauri
shell and a Leptos/WASM UI. The UI invokes a typed `get_app_info` operation;
the shell owns startup, immutable app state, logging, capabilities, CSP, and
the command adapter. The core has no Tauri, WebView2, Win32, HTTP, or
filesystem implementation dependency.

The shell exposes only the Phase 1 command and required Tauri core permissions.
Its CSP is local-only with narrowly scoped WASM and IPC directives. No remote
provider, credential, document, renderer, or telemetry behavior is part of this
phase.

## Current state

The production workspace exists at `windows/`. Rust formatting, workspace
checking, clippy with `-D warnings`, tests, release WASM build, release native
Tauri build, security validation, CI contract validation, native WebView2
launch, typed IPC rendering, and clean close were verified locally on
2026-08-17. Detailed results are in
`docs/windows/phase-01/EVIDENCE.md`, and the acceptance matrix is in
`docs/windows/phase-01/ACCEPTANCE_MATRIX.md`.

Phase 2 has not started. The macOS source and Phase 0 disposable artifacts
remain in their original locations.

## Related concepts

- [document-lifecycle](document-lifecycle.md) — the existing macOS document and watcher behavior.
- [document-architecture](document-architecture.md) — the existing semantic model and source relationship.
- [rendering-pipeline](rendering-pipeline.md) — the existing bundled Markdown/Mermaid renderer.
- [ai-assistant](ai-assistant.md) — the existing provider/proposal behavior.
