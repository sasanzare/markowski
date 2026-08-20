---
type: View
title: Windows workspace shell
description: The Phase 2 Windows desktop workspace with LTR application chrome, local RTL document fixtures, mode placeholders, and a structural AI pane.
resource: windows/apps/desktop-ui/src/app.rs
tags: [view, windows, shell, workspace, rtl, accessibility]
status: active
---

# Layout

The application root is explicitly LTR. Its workspace uses a central content
pane, an 18 px splitter, and a 280–520 px AI placeholder pane. The pane can be
hidden, which expands the central workspace, or resized by pointer and
keyboard. The Tauri window starts at 960×640 with a 900×600 minimum.

# Direction model

Persian and mixed fixtures set direction only on document content. English
chrome, mode labels, code-like fragments, numbers, and the Markowski identity
remain LTR. `bdi` and `unicode-bidi: isolate` keep inline `cargo test`,
`0.1.0`, and `Windows` readable without manual reversal.

# Visual states

The no-document state is a welcome shell with explicit Phase 3 placeholders.
Document fixtures expose distinct Preview, Editor, and Source foundation
panels. The AI pane is a complementary landmark whose copy explicitly says
that chat, providers, network, and secrets are not active.

Light, Dark, and System controls map to semantic CSS tokens. Focus-visible
styles and native control semantics provide the Phase 2 accessibility
foundation.

See [Windows UI state](../components/windows-ui-state.md) for the local state
contract and [Windows AppShell](../components/windows-shell.md) for composition.
