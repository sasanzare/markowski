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

* [windows architecture proposal](architecture/windows-architecture.md) - Phase 0 boundary and readiness record for the proposed Rust/Tauri 2/Leptos/WebView2 implementation. The detailed audit remains under `docs/windows/phase-00/`.
