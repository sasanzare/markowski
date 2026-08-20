---
type: Architecture
title: Windows architecture implementation
description: Phase 2 Windows Rust/Tauri/Leptos shell with typed local UI state, semantic themes, bilingual direction handling, and the Phase 1 security boundary.
resource: docs/windows/phase-02/PHASE_02_IMPLEMENTATION.md
tags: [architecture, windows, rust, tauri, leptos, webview2, ui, rtl, security]
status: active
---

# Purpose

This concept records the implemented Windows Phase 1 and Phase 2 foundation as
an extension of the existing MarkView macOS knowledge bundle. Production
Windows source lives under `windows/`; Windows planning and evidence remain
under `docs/windows/`.

## Contract

The implementation keeps a platform-neutral Rust core below a thin Tauri
shell and a Leptos/WASM UI. The UI invokes a typed `get_app_info` operation;
the shell owns startup, immutable app state, logging, capabilities, CSP, and
the command adapter. The core has no Tauri, WebView2, Win32, HTTP, or
filesystem implementation dependency.

The shell exposes only the Phase 1 command and required Tauri core permissions.
Its CSP is local-only with narrowly scoped WASM and IPC directives. Phase 2
adds no native command or permission. No remote provider, credential,
filesystem, document lifecycle, renderer, persistence, or telemetry behavior
is part of this phase.

## Current state

The production workspace exists at `windows/`. Phase 2 adds the AppShell,
toolbar, typed `WorkspaceMode`/`ThemePreference`/fixture state, direct-grid
workspace and resizable AI placeholder, semantic Light/Dark/System tokens,
local Persian/mixed fixtures, logical CSS direction handling, and accessible
keyboard controls. Rust gates, release WASM/native builds, security/CI
validators, native WebView2 launch, side-by-side layout, mode switching,
theme switching, pane resize, and clean close were verified locally on
2026-08-19. Detailed results are in
`docs/windows/phase-02/EVIDENCE.md`, with the acceptance matrix in
`docs/windows/phase-02/ACCEPTANCE_MATRIX.md`.

Phase 2 remains `PARTIAL` because this host only supplies native 125% scale
evidence; separate native evidence for 100%, 150%, and 200% scaling is still
missing. A distinct medium run at 1286×794 logical pixels was captured. The
macOS source and Phase 0 disposable artifacts remain in their original
locations.

## Related concepts

- [document-lifecycle](document-lifecycle.md) — the existing macOS document and watcher behavior.
- [document-architecture](document-architecture.md) — the existing semantic model and source relationship.
- [rendering-pipeline](rendering-pipeline.md) — the existing bundled Markdown/Mermaid renderer.
- [ai-assistant](ai-assistant.md) — the existing provider/proposal behavior.
- [windows-shell](../components/windows-shell.md) — the Windows Leptos shell and native bridge boundary.
- [windows-ui-state](../components/windows-ui-state.md) — typed session-only Phase 2 UI state.
- [windows-workspace-shell](../views/windows-workspace-shell.md) — the bilingual workspace and sidebar view contract.
