# Native WebDriver skeleton

This directory reserves the native Tauri/WebView2 E2E boundary described by
the Windows test strategy. Phase 2 has a real shell and deterministic UI
fixtures, but the current evidence run is manual through the actual native
window; it does not claim a WebDriver suite.

The first real suite should use the supported Tauri WebDriver route against a
release-like executable and should add scenarios only with the phase that
introduces the corresponding behavior. A browser-only preview test must not be
reported as native WebView2 evidence.

Required future evidence includes the executable path, WebView2 runtime,
offline/network state, test command, exit code, and captured failure artifact.
The current manual Phase 2 evidence records the executable hash, window sizes,
125% WebView scale, accessibility observations, interactions, and clean exit
under `docs/windows/phase-02/EVIDENCE.md`.
