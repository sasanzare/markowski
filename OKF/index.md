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

* [windows architecture](architecture/windows-architecture.md) - Implemented Phase 1 Rust/Tauri 2/Leptos/WebView2 foundation, typed IPC, local security baseline, and links to the phase evidence under `docs/windows/phase-01/`.
