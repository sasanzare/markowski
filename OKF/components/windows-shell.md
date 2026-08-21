---
type: Rust Component
title: Windows AppShell
description: The Windows Leptos application shell that composes the workspace and typed document lifecycle bridge while keeping filesystem authority native and local.
resource: windows/apps/desktop-ui/src/app.rs
tags: [component, windows, rust, leptos, shell, accessibility]
status: active
---

# What it does

`AppShell` is the production Windows root view. It owns a small `UiState`
bundle of Leptos signals and composes `TopBar`, `WorkspaceToolbar`,
`WorkspaceSurface`, `ResizableSplitter`, `AiSidebar`, and `StatusArea`.

Phase 3 adds typed `new_document`, `open_document`, `update_document_content`,
`save_document`, `save_document_as`, `reload_document`, and
`get_document_state` calls. The UI renders a deliberately plain textarea,
debounces edits, polls typed state, and starts autosave only for a persisted
path that is not in a conflict/missing/rename state. Native dialogs and
filesystem access remain in the Windows shell/platform boundary.

The AI pane is structural and local-only; it has no chat, provider, network,
secret, or telemetry path in this phase.

# Stable responsibilities

- Present Markowski Windows chrome and native bridge status.
- Keep mode, theme, fixture, sidebar visibility, width, and notices in local
  session state.
- Provide semantic buttons, select controls, tabs, a tabpanel, a complementary
  landmark, and an accessible separator.
- Keep document direction local to document content while the application root
  remains LTR.
- Make dirty New/Open/switch actions require an explicit discard confirmation
  in both UI flow and typed backend request data.
- Show typed saved/dirty/saving/external/conflict/missing/error status without
  exposing raw filesystem or OS error details.

The shell deliberately does not implement hashing, newline policy, atomic
replacement, or raw watcher interpretation. Those responsibilities belong to
the [Windows document domain](windows-document-lifecycle.md) and
[Windows filesystem adapter](windows-platform-filesystem.md).

See [Windows UI state](windows-ui-state.md) and the
[Windows workspace shell](../views/windows-workspace-shell.md).
