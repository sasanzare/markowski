---
okf_version: "0.2"
---

# Markowski — Knowledge Bundle

Markowski (internally still organized under the `MarkView` source target)
is a native macOS SwiftUI app for viewing and editing Markdown
files with a live preview (including Mermaid diagrams) and an AI writing
assistant. This bundle documents its architecture, components, and views
in [OKF](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md)
format so both humans and agents can navigate it without reading the
whole source tree first.

Start with [overview](overview.md) for the big picture, then drill into
whichever area you're touching.

# Top level

* [overview](overview.md) - What MarkView is, its stack, and its top-level structure.
* [log](log.md) - History of updates to this knowledge bundle.

# Sections

* [architecture/](architecture/) - How the major subsystems fit together.
* [components/](components/) - Individual services and model types, one concept each.
* [views/](views/) - SwiftUI views and their responsibilities.
* [playbooks/](playbooks/) - Step-by-step guides for common changes.

## Windows extension

* [windows architecture](architecture/windows-architecture.md) - Windows Rust/Tauri 2/Leptos/WebView2 boundary, typed IPC, local UI state, document lifecycle, and security baseline.
* [windows document lifecycle](architecture/windows-document-lifecycle.md) - Phase 3 state machine, revision-safe persistence, watcher reconciliation, and concurrency invariants.
* [windows shell](components/windows-shell.md) - The production Windows AppShell, typed lifecycle bridge, and close/switch safety boundary.
* [windows UI state](components/windows-ui-state.md) - Typed mode, theme, fixture, pane, and visibility state.
* [windows document domain](components/windows-document-lifecycle.md) - Platform-neutral Windows document state and save coordination.
* [windows platform filesystem](components/windows-platform-filesystem.md) - Windows atomic writes, native dialogs, and debounced watcher adapter.
* [windows workspace view](views/windows-workspace-shell.md) - The LTR application chrome, local RTL document fixtures, and AI pane.
