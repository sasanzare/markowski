# Native WebDriver skeleton

This directory reserves the native Tauri/WebView2 E2E boundary described by
the Windows test strategy. Phase 1 intentionally has no document, editor,
renderer, or provider scenarios to automate.

The first real suite should use the supported Tauri WebDriver route against a
release-like executable and should add scenarios only with the phase that
introduces the corresponding behavior. A browser-only preview test must not be
reported as native WebView2 evidence.

Required future evidence includes the executable path, WebView2 runtime,
offline/network state, test command, exit code, and captured failure artifact.
