# ADR-WIN-002: Tauri 2 as the thin desktop shell

- Status: Proposed
- Date: 2026-08-16
- Scope: Windows application shell

## Context

The master plan selects Tauri 2, and the product needs a native window,
filesystem dialogs, OS integration, typed IPC, and WebView2 without placing
business logic in the browser surface.

## Decision

Use Tauri 2 as a thin shell. It owns process/window lifecycle, capabilities,
typed command/event registration, dialogs, opener policy, and translation to
domain traits. Domain behavior remains in Rust crates; the Leptos frontend
receives DTOs and events.

## Alternatives and why rejected

- WinUI 3-only: native controls could help IME/DPI, but would reduce renderer
  reuse and depart from the selected architecture.
- Electron: rejected for the product’s local footprint/security goals and the
  explicit Tauri plan.
- Tauri commands containing all logic: rejected for coupling and security.

## Consequences

WebView2 availability and Tauri capability configuration become release gates.
The shell is small, but typed DTO evolution and capability reviews are required.

## Security

Capabilities are explicit per window; commands are allowlisted; remote origins
receive no native API access by default; no generic shell/filesystem command is
exposed.

## Testing

Compile a minimal smoke app, assert capability denial, exercise command schemas,
and run native WebDriver E2E against a release-like binary.

## Cross-platform

This ADR is Windows-specific. Shared domain and renderer tests remain portable;
the macOS Swift app remains unchanged in Phase 0.

## Open questions

Confirm exact Tauri plugin versions, capability file layout, and whether dialogs
and opener operations use official plugins or narrow custom commands.
