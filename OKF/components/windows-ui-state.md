---
type: Rust Component
title: Windows UI state
description: Strongly typed, session-only Phase 2 state for modes, themes, deterministic fixtures, sidebar visibility, and pane constraints.
resource: windows/apps/desktop-ui/src/state.rs
tags: [component, windows, rust, state, theme, rtl]
status: active
---

# State contract

The Phase 2 UI uses enums rather than stringly typed mode or theme values:

- `WorkspaceMode`: `Preview`, `Editor`, `Source`.
- `ThemePreference`: `System`, `Light`, `Dark`.
- `WorkspaceFixture`: empty, document placeholder, Persian, or mixed
  direction. Fixtures are UI-only and never read from disk.

Pane state is bounded by 280 px minimum, 520 px maximum, and 336 px default.
Visibility, width, and placeholder notices remain in Leptos signals for the
current session; no persistence abstraction was introduced.

The module contains pure tests for mode ordering, theme CSS values, fixture
direction/locality, and pane clamping. `markowski-core` remains free of fake
future document concepts.
