---
type: Architecture
title: Windows architecture proposal
description: Phase 0 knowledge of the proposed Rust, Tauri 2, Leptos, WebView2, document-safety, and platform boundaries for Windows.
resource: docs/windows/phase-00/WINDOWS_ARCHITECTURE.md
tags: [architecture, windows, rust, tauri, webview2]
status: proposed
---

# Purpose

This concept records the Windows architecture freeze from Phase 0. It extends
the existing MarkView macOS knowledge bundle; it does not claim that a Windows
workspace or native build exists.

## Contract

The Windows design keeps Markdown source as the document authority, separates a
platform-neutral Rust domain core from Tauri/WebView2/Windows adapters, treats
AI output as an untrusted proposal, and requires local-first persistence and
fail-closed document/secret safety. The detailed boundary, IPC, renderer, save,
and release contracts are maintained in the linked Phase 0 architecture
document.

## Current state

The production repository still has no Cargo/Tauri/Leptos workspace. The
remediation host verifies Rust MSVC `1.87.0`, Visual Studio Build Tools/MSVC,
Windows SDK `10.0.26100.0`, WebView2 `151.0.4129.86`, and the WASM target. The
existing official Leptos/Tauri 2 scaffold with a typed smoke bridge remains
isolated under the ignored `.artifacts/windows-phase0/` directory. Its release
WASM build, native Windows `.exe`, WebView2 launch, typed
`native-rust-bridge-ok` response, and clean close were verified on 2026-08-17.
The production architecture remains proposed, while Phase 0 is complete and
Phase 1 has not been started.

## Related concepts

- [document-lifecycle](document-lifecycle.md) — the existing macOS document and watcher behavior.
- [document-architecture](document-architecture.md) — the existing semantic model and source relationship.
- [rendering-pipeline](rendering-pipeline.md) — the existing bundled Markdown/Mermaid renderer.
- [ai-assistant](ai-assistant.md) — the existing provider/proposal behavior.
