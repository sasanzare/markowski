---
type: Rust Component
title: Windows AppShell
description: The Phase 2 Leptos application shell that composes chrome, workspace, modes, sidebar, and status while keeping the native boundary typed and local.
resource: windows/apps/desktop-ui/src/app.rs
tags: [component, windows, rust, leptos, shell, accessibility]
status: active
---

# What it does

`AppShell` is the production Windows root view. It owns a small `UiState`
bundle of Leptos signals and composes `TopBar`, `WorkspaceToolbar`,
`WorkspaceSurface`, `ResizableSplitter`, `AiSidebar`, and `StatusArea`.

The shell calls the existing typed `get_app_info` bridge only for native
identity/status. New/Open controls are explicit Phase 3 placeholders and do
not access files. The AI pane is structural and local-only; it has no chat,
provider, network, secret, or telemetry path.

# Stable responsibilities

- Present Markowski Windows chrome and native bridge status.
- Keep mode, theme, fixture, sidebar visibility, width, and notices in local
  session state.
- Provide semantic buttons, select controls, tabs, a tabpanel, a complementary
  landmark, and an accessible separator.
- Keep document direction local to fixture content while the application root
  remains LTR.

The shell deliberately does not create a document domain model. Phase 3 owns
real document lifecycle and filesystem behavior.

See [Windows UI state](windows-ui-state.md) and the
[Windows workspace shell](../views/windows-workspace-shell.md).
