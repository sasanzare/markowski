# Markowski Windows Phase 2 implementation

## Phase scope and status

Phase 2 establishes the Windows desktop shell, layout, theme, typography,
direction, accessibility, and local UI-state foundation authorized by the
Phase 2 execution prompt. It does not implement Phase 3 document lifecycle or
any filesystem, editor, renderer, search, persistence, credential, provider,
or packaging behavior.

**Phase status: PARTIAL.** The native shell and its required interactions are
implemented and evidenced, but the host was validated at 125% WebView scale
only. Separate native evidence for 100%, 150%, and 200% Windows scaling is
still open. Therefore
`PHASE_3_READINESS = NOT_READY`.

## Implemented shell

The production Windows boundary remains:

```text
windows/apps/desktop-ui/       Leptos/WASM shell, typed local UI state, CSS
windows/apps/desktop-shell/    Tauri 2 startup, typed get_app_info IPC
windows/crates/markowski-core/ platform-neutral app identity and errors
```

The Phase 2 UI now provides:

- Markowski Windows app chrome with native Windows title-bar behavior.
- Top command area with explicit New/Open Phase 3 placeholders, theme control,
  native bridge status, and an accessible AI sidebar toggle.
- A central workspace with deterministic no-document and document-fixture
  states.
- Preview, Editor, and Source mode tabs. Each mode is a distinct placeholder
  panel; none implements its future document behavior.
- A structural AI Assistant pane with a keyboard/pointer-resizable splitter,
  show/hide behavior, minimum/maximum constraints, and an explicit no-network
  boundary message.
- A status area exposing bridge status, local fixture/mode, pane visibility,
  pane width, and live WebView scale without logging document content.

## Local state model

`windows/apps/desktop-ui/src/state.rs` contains the small typed state model:

| Type | Values / responsibility |
| --- | --- |
| `WorkspaceMode` | `Preview`, `Editor`, `Source`; stable display labels and keyboard order. |
| `ThemePreference` | `System`, `Light`, `Dark`; semantic CSS values. |
| `WorkspaceFixture` | `Empty`, `DocumentPlaceholder`, `PersianDocument`, `MixedDirectionDocument`; UI-only fixture selection with local content direction. |
| `sidebar_visible` | Session-only pane visibility. |
| `sidebar_width` | Session-only width clamped to 280–520 px; default 336 px. |
| `notice` | Local placeholder feedback for future Phase 3 actions. |

No fake `Document`, `DocumentSession`, watcher, save service, or document
domain model was added to `markowski-core`.

## Layout decisions

The workspace uses a direct three-track grid when the sidebar is visible:

```text
central workspace | 18 px splitter | 280–520 px assistant pane
```

The grid track declaration is explicit both in CSS and in the reactive inline
layout style. The CSS keeps a 336 px fallback because WebView2 treated the
earlier custom-property-only `minmax()` declaration as invalid before the
runtime width was available. The inline declaration updates the full track
list when the local width signal changes, avoiding a layout feedback loop.
When hidden, the two side items use `display: none` and the central track is
expanded through the inline style.

The Tauri window declares a 900×600 minimum and starts at 960×640. CSS
breakpoints reduce nonessential labels while preserving keyboard controls.

## Theme system

Light, Dark, and System are represented by `ThemePreference`. CSS semantic
tokens cover the application background, surfaces, elevated surfaces, text
levels, borders, focus ring, interactive states, selection, status, and
accent roles. System mode uses the WebView `prefers-color-scheme` media query,
so a running WebView can follow an OS theme change without a native Win32
hook.

## Typography

The repository already contained tracked IRANSansX assets. No fonts were
downloaded. Four existing assets were copied into the Windows UI bundle:

```text
windows/apps/desktop-ui/assets/fonts/
  IRANSansX-Regular.ttf
  IRANSansX-DemiBold.ttf
  IRANSansX-Bold.ttf
  IRANSansXFaNum-Regular.ttf
```

The CSS declares these local faces with Windows UI and system fallbacks, plus
a monospace fallback for code-like placeholders. The source macOS font assets
were not changed.

## Persian / RTL architecture

The document root and application shell remain explicitly `dir="ltr"`.
Persian and mixed fixtures apply direction only to the document content
surface. Text fragments use local `dir` and `bdi` isolation; CSS uses logical
properties such as `margin-inline`, `padding-inline`, and
`border-inline-start`. The fixtures exercise Persian prose, `cargo test`,
`0.1.0`, `Windows`, and an explicit bidi-isolation sentence without manual
character reversal or Unicode direction-control hacks.

## Accessibility and keyboard foundation

The shell uses native buttons, select controls, headings, landmarks, a
tabpanel, an accessible splitter separator, labels, selected tab state, and
`aria-pressed`/`aria-hidden` state for the sidebar. Focus-visible styles are
centralized in CSS. Native validation exercised Tab, Shift+Tab, keyboard mode
and fixture controls, splitter keyboard resizing, Home/End constraints, and
clean show/hide transitions.

## Security and Phase 3 boundary

The existing Tauri capability allowlist and restrictive CSP were preserved.
No native permission or command was added for Phase 2. The static validator
rejects remote runtime assets and scans production Windows source for Phase 3
document-lifecycle concepts. New/Open controls report placeholders only;
they do not read, write, watch, persist, or log document data.

## Validation limitations

The native evidence was captured on Windows through the actual release
executable and WebView2 at a reported `devicePixelRatio` of 1.25 (125%). The
standard window screenshot was 962×671 logical pixels and the maximized
screenshot was 1536×816 logical pixels. The configured minimum is 900×600.
This is sufficient for native startup, shell, small/standard, and large
layout evidence. A distinct medium run was also captured at 1286×794 logical
pixels at live 125% scale. This is not evidence for 100%, 150%, or 200%
scaling; those open gates keep the phase status `PARTIAL`.

## Primary changed files

- `windows/apps/desktop-ui/src/app.rs`
- `windows/apps/desktop-ui/src/state.rs`
- `windows/apps/desktop-ui/styles.css`
- `windows/apps/desktop-ui/index.html`
- `windows/apps/desktop-ui/Cargo.toml`
- `windows/apps/desktop-ui/assets/fonts/*`
- `windows/apps/desktop-shell/tauri.conf.json`
- `windows/scripts/validate-phase2.ps1`
- `docs/windows/phase-02/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-02/EVIDENCE.md`
