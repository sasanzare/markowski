# Markowski Windows Phase 2 evidence

## Evidence identity

- Date: 2026-08-20
- Branch: `main`
- Starting/base HEAD: `e22e84705dc15f047c153d178d3e7a5a4fdf53db`
- Final HEAD: unchanged; no commit was created.
- Native artifact: `windows/target/release/markowski-desktop-shell.exe`
- Native SHA-256: `8F42636B23E7A2559F961528DBC8A336C3214CE12D9695A547C780E059287AC8`
- Fixed 100% run: native window id `395174`; `962×672` logical pixels at
  origin `(59,52)`; live WebView scale `100%`.
- Minimum-window run: `902×632` logical pixels at the same origin; this is the
  configured `900×600` client minimum plus the native frame.
- Distinct medium run: `1286×794` logical pixels at window origin `(2,8)`,
  live WebView scale `125%`; native window id `1705278`.
- 150% validation run: native window id `132846`; standard `963×671` logical
  pixels and minimum `903×632` logical pixels; live WebView scale `150%`.
- 200% validation run: native window id `67176`; visible native/WebView capture
  `955×540` logical pixels at origin `(11,0)`; live WebView scale `200%`.
- Native UI evidence notes: [`.artifacts/windows-phase2/native-evidence.md`](../../../.artifacts/windows-phase2/native-evidence.md)

The native evidence was captured against the actual release executable through
the Windows computer-use runtime. The runtime displayed screenshots and
accessibility trees during the checks; it does not persist those screenshot
payloads as repository files. The artifact above therefore records the exact
observations and limitations without pretending that binary screenshot files
exist.

The prior 125% interaction sequence was run after the explicit grid fallback
and inline track declaration were in place. During the new 100% run, the
reported splitter value changed while the visible grid did not; this was a
real layout defect. The minimal Phase 2 fix changes the reactive
`grid-template-columns` update to an individual Leptos style property in
`windows/apps/desktop-ui/src/app.rs`. The fixed release artifact was rebuilt,
relaunched, rechecked, and exited cleanly.

## Required command gates

All commands below were executed after the final Phase 2 code change.

| Command | Result |
| --- | --- |
| `cargo fmt --all -- --check` | PASS |
| `cargo check --workspace` | PASS; only the existing future-incompatibility warning for `proc-macro-error2` was printed. |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | PASS; same non-fatal future-incompatibility warning. |
| `cargo test --workspace` | PASS; 10 passed, 0 failed. |
| `D:\All projects\.cargo-markowski\bin\trunk.exe build --release` | PASS. |
| `D:\All projects\.cargo-markowski\bin\cargo-tauri.exe build --no-bundle --ci` | PASS; executable produced at the native artifact path. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1` | PASS. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1` | PASS. |
| `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1` | PASS. |
| `git diff --check` | PASS; final result recorded in HANDOFF. |

## Native state observations

The standard release window started from the configured 960×640 window and
was reported by the runtime as a 962×671 logical-pixel screenshot. The UI
status rendered `WebView scale 125%`. The native accessibility tree exposed
the Markowski heading, primary buttons, theme combo, AI toggle, mode tabs,
fixture combo, document tabpanel, splitter separator, complementary AI
sidebar, and status metrics.

The following states were observed in the real WebView2 window:

| State | Observation |
| --- | --- |
| No document | Welcome shell, explicit Phase 3 New/Open placeholders, no document data message, and visible side pane. |
| Document fixture | Persian and mixed fixtures rendered as local UI-only content; status changed to `Document`. |
| Preview | Rendered workspace placeholder panel. |
| Editor | Visual editor placeholder with stable heading/paragraph/code blocks. |
| Source | Markdown source placeholder; no editable source control. |
| AI visible | Side-by-side pane, accessible `complementary` landmark, `AI on` status. |
| AI hidden | Pane removed from the accessibility tree, central content expanded, `AI off` status. |
| Light | Light surfaces, readable text, visible focus, pane separator, and active theme control. |
| Dark | Dark semantic surfaces, readable text, visible focus, pane separator, and active theme control. |
| System | Default System selection rendered and tracked in the native shell; media-query fallback is in CSS. |
| Persian | Real Persian paragraph flowed RTL locally while Markowski chrome remained LTR. |
| Mixed | Persian prose, `cargo test`, `0.1.0`, `Windows`, and bidi-isolation text remained readable. |

## Native 100% DPI validation

The host Windows Display Scale was manually set to 100% before the fixed
production run. The real release executable launched with title `Markowski`,
WebView2 rendered the complete shell, and the status area reported
`WebView scale 100%`. The accessibility tree exposed the application heading,
toolbar controls, Preview/Editor/Source tabs, fixture selector, document
tabpanel, splitter, AI complementary landmark, and status metrics.

The standard native screenshot was `962×672` logical pixels. The toolbar was
fully visible; labels were readable; Preview, Editor, and Source were each
selected successfully; and the AI sidebar was usable both visible and hidden.
The splitter visibly moved from its default `338 px` to `280 px` by pointer
drag, to `354 px` with `Left`, and to `520 px` with `End`; the visible focus
outline remained on the splitter during keyboard traversal. No overlap or
broken layout was observed after the fix.

The Persian fixture rendered a local RTL paragraph while the application chrome
remained LTR. The mixed fixture kept Persian prose, `cargo test`, `0.1.0`,
`Windows`, and bidi-isolation text readable. At the native minimum boundary,
the screenshot was `902×632` logical pixels (configured client minimum
`900×600`); toolbar, mode controls, fixture selector, both panes, and labels
remained usable, and further inward resize was clamped. `Alt+F4` closed the
validated process, and a fresh app enumeration returned no remaining
`markowski-desktop-shell` window.

This supports `AC-WIN-P02-027 = PASS`. It does not change the separate 200%
gate.

## Medium window validation

The production release executable was run in a distinct `1286×794` logical-pixel
window at origin `(2,8)`, approximately the requested `1280×800` size. The
toolbar was fully visible; Preview-to-Editor mode switching worked; the central
workspace, AI sidebar, splitter, and status area remained usable without
overlap. Persian and mixed RTL/LTR fixtures were readable, including the
embedded `cargo test`, `0.1.0`, and `Windows` tokens. Pointer dragging changed
the pane from `336 px` to `296 px`, and Tab traversal left a visible blue focus
outline on the splitter. This supports `AC-WIN-P02-024 = PASS`.

## Native 150% DPI validation

The host Windows Display Scale was manually set to 150% before this run. The
current production release executable launched with title `Markowski`; its
native window started at `963×671` logical pixels, and the live status and
accessibility tree both reported `WebView scale 150%`. The release artifact
hash was unchanged at
`8F42636B23E7A2559F961528DBC8A336C3214CE12D9695A547C780E059287AC8`.

The toolbar was fully visible and labels were readable. Preview, Editor, and
Source were each selected successfully. The AI sidebar was toggled off and
back on; the complementary landmark disappeared and returned, while the
central workspace expanded and restored without overlap. Pointer dragging
changed the splitter from its default `336 px` to `407 px`. Blue focus outlines
were visible on mode/fixture controls and the splitter. No overlap or broken
layout was observed.

The Persian fixture rendered as a local RTL document while the application
chrome remained LTR. The accessibility tree contained the Persian text plus
`0.1.0` and `Windows`, and the status changed to `Document · Preview mode`.
The mixed fixture contained Persian prose, `cargo test`, `0.1.0`, `Windows`,
and the bidi-isolation note; the mixed content remained readable without
flipping the application chrome.

The configured minimum boundary was reached at `903×632` logical pixels,
corresponding to the configured `900×600` client minimum plus the native frame.
At that boundary the toolbar, mode controls, fixture selector, both panes, and
labels remained usable. Editor and Source remained selectable; the AI sidebar
was hidden and restored without overlap; and the splitter moved from `407 px`
to `437 px`. `Alt+F4` closed the validated process; a fresh native app/window
enumeration returned no remaining `markowski-desktop-shell` window, and the
process check returned no remaining process.

This supports `AC-WIN-P02-029 = PASS`.

## Native 200% DPI validation

The host Windows Display Scale was manually set to 200% before this run. The
current production release executable was launched directly from
`windows/target/release/markowski-desktop-shell.exe`, with native window id
`67176`, title `Markowski`, and SHA-256
`8F42636B23E7A2559F961528DBC8A336C3214CE12D9695A547C780E059287AC8`. The
initial native accessibility tree and status area both reported
`WebView scale 200%`.

The computer-use runtime returned a `955×540` logical-pixel visible capture at
origin `(11,0)`. At 200% the host desktop constrained the visible lower
boundary of the configured `960×640` window; this records host geometry and
does not infer a different configured native minimum. The shell was brought
back to its top view in the same native window before the final layout
inspection.

The toolbar was fully visible and not clipped; the Markowski identity, theme
control, AI toggle, Preview/Editor/Source controls, and fixture selector were
readable. The document fixture enabled Preview, Editor, and Source in turn,
with status changing to `Document · Preview mode`, `Document · Editor mode`,
and `Document · Source mode`; the corresponding foundation panels rendered
without overlap.

The AI sidebar was hidden and shown again. The `AI off` state removed the
complementary landmark and expanded the central workspace; the `AI on` state
restored the sidebar without overlap. Pointer dragging changed the splitter
from `336 px` to `377 px`, and keyboard resizing after Tab focus changed it
to `361 px`. The focused splitter showed a visible blue focus indicator and
the pane remained usable after both changes.

The Persian fixture rendered
`سلام، این یک سند فارسی برای آزمایش Markowski است.` plus `0.1.0` and
`Windows` in a local RTL document surface while the application chrome stayed
LTR. The mixed fixture kept `cargo test`, `0.1.0`, `Windows`, and the
`bidi isolation` note readable alongside Persian prose. No overlap, clipped
toolbar, or broken layout was observed in the visible high-DPI viewport.

The host-constrained 200% viewport remained usable at the lower visible
boundary: toolbar, mode controls, fixture selector, document surface, AI pane,
splitter, and labels remained accessible and usable. The configured native
minimum remains `900×600`; the 200% host desktop did not expose a full
`900×600` capture, so no unsupported exact minimum-window dimensions are
claimed here. `Alt+F4` closed the application, and fresh app enumeration
returned no remaining `markowski-desktop-shell` window.

No real 200% DPI defect was found, so no source change or rebuild was needed.
This supports `AC-WIN-P02-030 = PASS`.

## Pane and keyboard observations

- Pointer drag moved the pane from 280 px to 350 px in the native window.
- Splitter keyboard resize changed the width to 320 px with `Right`.
- `End` clamped to 520 px; `Home` clamped to 280 px.
- Tab focus reached the sidebar hide button; Shift+Tab reached the splitter.
- The focused splitter showed a visible blue focus outline.
- The mode and fixture controls were operated with native keyboard selection.
- The AI toggle was operated through its semantic button and `aria-pressed`
  state.

## Window-size evidence

| Scenario | Actual native evidence |
| --- | --- |
| Small/standard | 960×640 configured window; 962×672 logical screenshot at 100%; no overlap and side pane usable after the splitter fix. |
| Medium | 1286×794 logical pixels at origin (2,8), live 125%; toolbar, modes, workspace, AI pane, splitter, Persian/mixed fixtures, no-overlap layout, and visible focus inspected. |
| Large | Maximized 1536×816 captured screenshot; side pane and controls remained visible. |
| Minimum | 902×632 native screenshot at the configured 900×600 client minimum; toolbar, modes, fixture, AI pane, splitter, and labels remained usable. |
| 150% validation | 963×671 standard and 903×632 minimum logical pixels at live 150%; toolbar, modes, Persian/mixed fixtures, AI pane, splitter, focus, and clean exit inspected. |
| 200% validation | Native window id 67176; `955×540` visible logical pixels at origin `(11,0)`, live `WebView scale 200%`; toolbar, modes, Persian/mixed fixtures, AI pane, splitter, focus, no-overlap layout, and clean exit inspected. |

## DPI evidence and limitation

100%, 125%, 150%, and 200% are evidenced by live status labels and native
screenshots/accessibility trees from the actual release executable. The 200%
capture includes the host desktop's visible-height limitation at the
configured `960×640` window; the observed shell remained usable within that
viewport, and the configured `900×600` native minimum was not replaced or
inferred from the capture. CSS relative sizing, logical properties, and the
280–520 px pane constraint are supporting implementation details, not
substitutes for the native DPI evidence.

## Security revalidation

The Phase 2 validator confirmed the unchanged five core permissions plus the
existing `allow-get-app-info` command permission, restrictive CSP, explicit
LTR root, local assets, and absence of Phase 3 lifecycle terms in production
Windows source. No filesystem, shell, updater, unrestricted HTTP, credential,
telemetry, or remote JavaScript capability was added.

## Preservation checks

The final diff was restricted to Windows production code/assets, Windows
documentation/scripts, root handoff, OKF, and the Phase 2 artifact notes.
`MarkView/`, `MarkViewTests/`, and `MarkView.xcodeproj/` were not modified.
