---
type: Architecture
title: Windows architecture implementation
description: Windows Rust/Tauri/Leptos shell with typed local UI state, document lifecycle safety, semantic themes, bilingual direction handling, and the least-privilege security boundary.
resource: docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md
tags: [architecture, windows, rust, tauri, leptos, webview2, ui, rtl, security]
status: active
---

# Purpose

This concept records the implemented Windows foundation and Phase 3 document
lifecycle as an extension of the existing MarkView macOS knowledge bundle.
Production Windows source lives under `windows/`; Windows planning and
evidence remain under `docs/windows/`.

## Contract

The implementation keeps a platform-neutral Rust document domain below a thin
Tauri shell and a Leptos/WASM UI. The shell owns startup, state coordination,
logging, capabilities, CSP, typed commands, native dialogs, and watcher
lifecycle. The domain has no Tauri, WebView2, Win32, HTTP, or direct filesystem
implementation dependency. The Windows adapter owns stable reads, flushed
same-directory replacement, native dialogs, and debounced `notify` events.

The capability set remains the Phase 2 least-privilege core allowlist. The
WebView has no generic filesystem, shell, process, network, credential, or
persistence permission. Markdown files remain the authoritative document
source; Phase 3 adds no database or durable settings.

## Current state

The production workspace exists at `windows/`. Phase 2 supplies the AppShell,
toolbar, typed `WorkspaceMode`/`ThemePreference` state, direct-grid workspace,
resizable AI placeholder, semantic Light/Dark/System tokens, local Persian/mixed
direction handling, and accessible controls. Phase 3 adds the document domain,
Windows filesystem adapter, typed lifecycle commands, safe New/Open/Save/Save
As/Reload behavior, conflict protection, watcher reconciliation, a plain
textarea lifecycle surface, and persisted-path debounced autosave.

Phase 4 Source Editor, Phase 5 Markdown/Mermaid preview, and Phase 8 durable
persistence remain outside this architecture. Current Phase 3 status and
native evidence are authoritative in `docs/windows/phase-03/`.

## Related concepts

- [document-lifecycle](document-lifecycle.md) — the existing macOS document and watcher behavior.
- [windows-document-lifecycle](windows-document-lifecycle.md) — the Windows Phase 3 state machine and filesystem safety contract.
- [document-architecture](document-architecture.md) — the existing semantic model and source relationship.
- [rendering-pipeline](rendering-pipeline.md) — the existing bundled Markdown/Mermaid renderer.
- [ai-assistant](ai-assistant.md) — the existing provider/proposal behavior.
- [windows-shell](../components/windows-shell.md) — the Windows Leptos shell and native bridge boundary.
- [windows-document-lifecycle](../components/windows-document-lifecycle.md) — the platform-neutral document domain.
- [windows-platform-filesystem](../components/windows-platform-filesystem.md) — the Windows filesystem and watcher adapter.
- [windows-ui-state](../components/windows-ui-state.md) — typed session-only Phase 2 UI state.
- [windows-workspace-shell](../views/windows-workspace-shell.md) — the bilingual workspace and sidebar view contract.
