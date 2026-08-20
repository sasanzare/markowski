# Project Handoff

## Last Updated

2026-08-20

## Project Summary

Markowski is a native macOS SwiftUI Markdown application documented under
`OKF/`. The repository also contains the production Windows Rust/Tauri 2/
Leptos/WebView2 boundary under `windows/`. Phase 1 established the typed
native foundation; this task implemented the authorized Phase 2 desktop shell
without beginning Phase 3 document lifecycle work.

## Current Objective

Complete the Phase 2 Windows Shell, Layout, Theme, RTL/LTR Foundation within
the authorized scope, preserve the Phase 1 security boundary, and leave a
truthful acceptance/evidence record. Do not start Phase 3.

## Current Phase or Milestone

`PHASE_STATUS = COMPLETE`
`PHASE_3_READINESS = READY`

The shell implementation and native interaction evidence are complete for the
validated host conditions. Native 100%, 150%, and 200% evidence are recorded
from the fixed production release artifact. All 51 Phase 2 acceptance
criteria are reconciled to PASS; Phase 3 remains explicitly out of scope.

## Repository State

- Repository path: `D:\All projects\markowski`
- Current branch: `main`
- Base or starting commit: `e22e84705dc15f047c153d178d3e7a5a4fdf53db`
- Current HEAD: `e22e84705dc15f047c153d178d3e7a5a4fdf53db`
- HEAD summary: `feat(windows): add Phase 1 Rust/Tauri foundation`
- Phase 0+1 commit present: yes; HEAD is unchanged during this task.
- Working tree status: uncommitted Phase 2 implementation, the minimal
  splitter layout fix, documentation, OKF, and handoff changes; ignored build
  output remains outside the tracked change set.
- Staged changes: none.
- Unstaged tracked changes: `HANDOFF.md`, Windows README/security/e2e docs,
  Windows Tauri/UI source/configuration/lockfile, OKF indexes/concepts/log,
  and Phase 2 validator.
- Untracked files: Phase 2 docs, Windows UI state module, four Windows font
  assets, and three Windows OKF concepts. `.artifacts/windows-phase2/` is
  ignored and contains the persistent textual native evidence note.

## Completed Work

- Verified the clean Phase 1 baseline before implementation: formatting,
  workspace check, strict Clippy, workspace tests, release WASM/native builds,
  native launch, typed bridge rendering, security, and CI validation.
- Added a production `AppShell` with Markowski Windows chrome, command area,
  workspace toolbar, mode tabs, local fixture selector, document surface,
  AI pane, splitter, and status metrics.
- Added typed session-only `WorkspaceMode`, `ThemePreference`,
  `WorkspaceFixture`, pane bounds, and resize math in `src/state.rs` with four
  pure Rust tests.
- Added deterministic no-document, document-placeholder, Persian, and mixed
  RTL/LTR states. New/Open remain explicit Phase 3 placeholders and do not
  touch the filesystem.
- Added Preview/Editor/Source foundation panels without implementing real
  Markdown editing, rendering, or source authority.
- Added a pointer- and keyboard-resizable AI placeholder with 280–520 px
  bounds, 336 px default, visible/hidden state, and accessible semantics.
- Added Light/Dark/System semantic CSS tokens, local `prefers-color-scheme`
  behavior, logical CSS properties, explicit LTR application chrome, local
  document direction, bidi isolation, and reduced-motion/focus styles.
- Reused four existing tracked IRANSansX font assets by bundling copies under
  the Windows UI; no external font download was performed.
- Added 900×600 minimum native window configuration and Phase 2 static
  security/source validation.
- Captured native Windows evidence on the release executable: standard
  962×671 screenshot at live 125% WebView scale, maximized 1536×816 screenshot,
  Persian/mixed fixtures, modes, themes, sidebar toggle, pane drag/keyboard
  resize, focus, and clean exit.
- Captured a distinct medium native run at `1286×794` logical pixels at
  origin `(2,8)` and live 125% scale. Toolbar, Preview-to-Editor switching,
  central workspace, AI sidebar, splitter drag (`336 px` to `296 px`), Persian
  and mixed fixtures, no overlap, and visible splitter focus were inspected.
- During the native 100% run, found and minimally fixed a real WebView2 layout
  defect: the reactive splitter value changed in status/ARIA while the visible
  grid track stayed at its initial width. The fixed release artifact uses an
  individual reactive `grid-template-columns` style property, then visibly
  resized the pane by pointer and keyboard at 100%.
- Captured fixed native 100% evidence at `962×672` logical pixels with live
  `WebView scale 100%`, Persian and mixed RTL/LTR fixtures, all three mode
  controls, AI show/hide, visible focus, splitter bounds, and clean exit.
- Captured the native minimum-window boundary at `902×632` logical pixels,
  corresponding to the configured `900×600` client minimum; the toolbar,
  controls, panes, and labels remained usable without overlap.
- Revalidated the current production release artifact at the manually
  configured 150% host scale: live `WebView scale 150%`, `963×671` standard and
  `903×632` minimum logical pixels, all mode controls, AI show/hide, splitter
  drag, focus, Persian/mixed RTL-LTR fixtures, readable labels, no overlap, and
  clean exit. No 150% defect was found, so no source change or rebuild was
  needed.
- Revalidated the current production release artifact at the manually
  configured 200% host scale: live `WebView scale 200%`, native window id
  `67176`, and a `955×540` logical-pixel visible capture at origin
  `(11,0)`. Toolbar/labels, Preview/Editor/Source, AI show/hide, splitter
  pointer/keyboard resize, Persian/mixed RTL-LTR fixtures, visible focus,
  no-overlap layout, host-constrained minimum viewport, and clean exit all
  passed. No 200% defect was found, so no source change or rebuild was needed.
- Updated Phase 2 docs, README/security notes, canonical OKF concepts/indexes,
  and this handoff.

## Work in Progress

No required implementation or acceptance work remains in the authorized Phase 2
scope. Phase 2 is complete; Phase 3 was not started.

## Remaining Work

- No Phase 2 work remains.
- A separate user-authorized prompt is required before any Phase 3 work.

## Exact Next Steps

1. Stop after this report; Phase 2 is complete and Phase 3 has not started.
2. Await a separate user-authorized prompt before implementing or validating
   Phase 3 document lifecycle work.

## Files Created

- `docs/windows/phase-02/PHASE_02_IMPLEMENTATION.md`
- `docs/windows/phase-02/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-02/EVIDENCE.md`
- `OKF/components/windows-shell.md`
- `OKF/components/windows-ui-state.md`
- `OKF/views/windows-workspace-shell.md`
- `windows/apps/desktop-ui/src/state.rs`
- `windows/apps/desktop-ui/assets/fonts/IRANSansX-Regular.ttf`
- `windows/apps/desktop-ui/assets/fonts/IRANSansX-DemiBold.ttf`
- `windows/apps/desktop-ui/assets/fonts/IRANSansX-Bold.ttf`
- `windows/apps/desktop-ui/assets/fonts/IRANSansXFaNum-Regular.ttf`
- `windows/scripts/validate-phase2.ps1`
- `.artifacts/windows-phase2/native-evidence.md` (ignored evidence note)

## Files Modified

- `HANDOFF.md`
- `OKF/index.md`
- `OKF/architecture/index.md`
- `OKF/architecture/windows-architecture.md`
- `OKF/components/index.md`
- `OKF/views/index.md`
- `OKF/log.md`
- `windows/Cargo.lock`
- `windows/README.md`
- `windows/SECURITY_CHECKS.md`
- `windows/apps/desktop-shell/tauri.conf.json`
- `windows/apps/desktop-ui/Cargo.toml`
- `windows/apps/desktop-ui/index.html`
- `windows/apps/desktop-ui/src/app.rs`
- `windows/apps/desktop-ui/src/main.rs`
- `windows/apps/desktop-ui/styles.css`
- `windows/tests/e2e/README.md`

## Important Architecture and Design Decisions

- Production Windows code remains isolated under `windows/`; the macOS
  `MarkView/`, `MarkViewTests/`, and `MarkView.xcodeproj/` trees are untouched.
- `markowski-core` remains platform-neutral and contains no fake future
  `Document` or `DocumentSession` concepts.
- The only native command remains typed `get_app_info`; Phase 2 adds no
  permission or command.
- UI state is typed and session-only. No persistence, filesystem, watcher,
  credential, provider, telemetry, or network path was introduced.
- The application root is explicitly LTR. Document content owns local RTL or
  mixed direction; the whole UI is never flipped because Persian is present.
- The workspace uses a direct grid with a valid fixed CSS fallback and a full
  reactive individual `grid-template-columns` style property. This avoids the
  WebView2 stale-track behavior found when a reactive whole-style attribute
  updated the status/ARIA value but did not visibly update the grid track.
- Existing local IRANSansX assets are reused; font licensing/source was not
  changed or supplemented from the internet.

## Commands Executed

From `windows/`:

- `cargo fmt --all -- --check`
- `cargo check --workspace`
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- `cargo test --workspace`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1`
- `powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1`

Release commands:

- `D:\All projects\.cargo-markowski\bin\trunk.exe build --release` from
  `windows/apps/desktop-ui/`.
- `D:\All projects\.cargo-markowski\bin\cargo-tauri.exe build --no-bundle --ci`
  from `windows/`.
- `Start-Process ...\\windows\\target\\release\\markowski-desktop-shell.exe`
  with the production working directory for native launch.
- Computer-use native launch and interaction of the current release artifact at
  the manually configured 150% host scale; `Alt+F4` and fresh app/window
  enumeration for clean exit.
- Computer-use native launch and interaction of the current release artifact at
  the manually configured 200% host scale; live scale/status inspection,
  toolbar/mode/fixture/sidebar/splitter/focus/RTL checks, `Alt+F4`, and
  fresh app enumeration for clean exit.
- `Get-FileHash -Algorithm SHA256` for the final unbundled executable.
- `Get-Process -Name markowski-desktop-shell` after exit; no process remained.
- `git diff --check`, final `git status --short --untracked-files=all`, and
  final diff inspection.

The post-fix Tauri build hook required the verified local Trunk bin directory
to be present in `PATH`; the production build then completed successfully.

The inherited `NO_COLOR=1` environment initially caused Trunk's boolean
parser to reject a build hook; final release commands explicitly normalized
`NO_COLOR=false` and passed.

## Validation and Test Results

- `cargo fmt --all -- --check`: PASS.
- `cargo check --workspace`: PASS; existing non-fatal future-incompatibility
  advisory for `proc-macro-error2` only.
- strict workspace Clippy: PASS with zero denied warnings.
- `cargo test --workspace`: PASS; 10 passed, 0 failed (3 core, 3 shell, 4 UI
  state; doc-tests had no tests).
- Trunk release build: PASS.
- Tauri native release build: PASS; final artifact exists at
  `windows/target/release/markowski-desktop-shell.exe`.
- Phase 2 static validator: PASS.
- Phase 1 security validator: PASS.
- Phase 1 CI contract validator: PASS.
- During the 2026-08-20 evidence-only remediation pass, the Phase 2,
  security, and CI validators were rerun; all three returned PASS.
- Fixed native 100% launch: PASS; WebView2 rendered the shell, the visible
  splitter moved at 280/338/354/520 px checks, the required fixtures and focus
  states remained usable, and the process exited cleanly.
- Native 100% standard evidence: `962×672` logical pixels with live
  `WebView scale 100%`.
- Native 100% minimum-window evidence: `902×632` logical pixels at the
  configured `900×600` client minimum; further inward resize was clamped.
- Native 150% validation: PASS; the current release artifact reported live
  `WebView scale 150%` at `963×671` standard and `903×632` minimum logical
  pixels. Toolbar/labels, Preview/Editor/Source, AI sidebar, splitter (`336 px`
  to `407 px`, then `437 px` at minimum), Persian/mixed RTL-LTR fixtures,
  visible focus, no-overlap layout, and clean exit were inspected.
- Native 200% validation: PASS; the current release artifact reported
  `WebView scale 200%` at native window id `67176` with a
  `955×540` visible logical-pixel capture at origin `(11,0)`.
  Toolbar/labels, all three modes, AI hide/show, splitter drag/keyboard resize,
  Persian/mixed RTL-LTR fixtures, visible focus, no-overlap layout, and clean
  exit were inspected. The host constrained the visible lower boundary at this
  scale; no unsupported exact `900×600` capture is claimed.
- Final native artifact SHA-256:
  `8F42636B23E7A2559F961528DBC8A336C3214CE12D9695A547C780E059287AC8`.

## Known Issues and Blockers

None for Phase 2. `AC-WIN-P02-030` is PASS and all 51 Phase 2 acceptance
criteria are reconciled to PASS. Phase 3 remains unstarted by instruction.

## Risks and Assumptions

- Native evidence includes the current Windows host at 100% WebView scale, a
  distinct 1286×794 medium run at 125%, a separate 150% run including the
  configured minimum, and a 200% run with live status/accessibility evidence.
- The standard 100% window evidence is 962×672 logical pixels, the minimum is
  902×632 logical pixels for a configured 900×600 client minimum, and the
  150% evidence is 963×671 standard and 903×632 at the same configured client
  minimum; the 200% visible capture is 955×540 logical pixels at origin
  (11,0) because the host desktop constrained the lower visible boundary at
  that scale. The earlier maximized evidence is 1536×816.
- Native evidence was captured manually through the computer-use runtime;
  screenshot payloads were inspected live but are not persisted as binary
  repository files. The durable textual record is
  `.artifacts/windows-phase2/native-evidence.md`.
- The release artifact is unbundled and unsigned. No installer, signing, or
  packaging claim is made.

## Database or Migration State

Not applicable. Phase 2 adds no database, persistence layer, or migration.

## Configuration and Environment Notes

- Host: Windows MSVC with Rust `1.97.1`; targets include
  `x86_64-pc-windows-msvc` and `wasm32-unknown-unknown`.
- Dedicated Cargo/tool cache: `D:\All projects\.cargo-markowski`.
- Verified local tools: Trunk `0.21.14`, cargo-tauri `2.11.4`.
- Tauri hook working directory was verified as `windows/apps`; it runs
  `cd desktop-ui && trunk build --release`.
- WebView2 is local and no external network/provider/secret access was used.

## Uncommitted or Partially Applied Changes

All Phase 2 code, the minimal splitter layout fix, docs, OKF changes, fonts,
and this handoff are uncommitted;
the user did not authorize a commit. No changes were staged. No reset,
checkout, branch change, push, force-push, rebase, or history rewrite was
performed. Ignored `target/`, frontend `dist/`, and `.artifacts/windows-phase2/`
outputs are not part of the tracked Git change set.

## Recovery or Rollback Notes

Review the final Git diff before any commit or rollback decision. Production
Windows changes are isolated under `windows/`; Phase 2 documentation is under
`docs/windows/phase-02/`; OKF additions are linked from their indexes. Do not
discard unrelated existing files or use destructive Git cleanup.

## Related Documentation

- `docs/windows/MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`
- `docs/windows/phase-00/`
- `docs/windows/phase-01/PHASE_01_IMPLEMENTATION.md`
- `docs/windows/phase-01/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-01/EVIDENCE.md`
- `docs/windows/phase-02/PHASE_02_IMPLEMENTATION.md`
- `docs/windows/phase-02/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-02/EVIDENCE.md`
- `.artifacts/windows-phase2/native-evidence.md`
- `windows/README.md`
- `windows/SECURITY_CHECKS.md`
- `OKF/architecture/windows-architecture.md`

## Notes for the Next Agent

Treat the Phase 2 source, evidence, and acceptance matrix as the current source
of truth. All 51 Phase 2 criteria are PASS, `PHASE_STATUS = COMPLETE`, and
`PHASE_3_READINESS = READY`. Do not start Phase 3, add filesystem
permissions, create a document model, or modify the macOS source without a new
user prompt.
