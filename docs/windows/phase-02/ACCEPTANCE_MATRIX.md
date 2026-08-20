# Markowski Windows Phase 2 acceptance matrix

Phase 2 is reported as `COMPLETE`. `PASS` means the criterion has
implementation and validation evidence.

Current mandatory-gate summary after the native 200% run: `PASS: 51`,
`FAIL: 0`, `PARTIAL: 0`, `BLOCKED: 0`, `OPEN: 0`.

`Phase 2 Final Status = COMPLETE`
`Phase 3 Readiness = READY`

| ID | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| AC-WIN-P02-001 | Git baseline recorded | PASS | Root `HANDOFF.md` and final Git inspection. |
| AC-WIN-P02-002 | Phase 1 regression gates pass | PASS | `cargo fmt --check`, `check`, `clippy`, `test`; release and native rebuilds. |
| AC-WIN-P02-003 | production AppShell implemented | PASS | `windows/apps/desktop-ui/src/app.rs`; native launch evidence. |
| AC-WIN-P02-004 | no-document state implemented | PASS | Empty workspace fixture and native accessibility/screenshot evidence. |
| AC-WIN-P02-005 | document-placeholder state implemented | PASS | Deterministic local fixture enum and placeholder panels. |
| AC-WIN-P02-006 | Preview/Editor/Source mode container implemented | PASS | Typed mode enum, tabs, three native placeholder states. |
| AC-WIN-P02-007 | AI sidebar structural placeholder implemented | PASS | `AiSidebar`, semantic complementary landmark, native side-by-side evidence. |
| AC-WIN-P02-008 | sidebar show/hide works | PASS | Native `AI on`/`AI off` status and accessibility tree checks. |
| AC-WIN-P02-009 | resizable pane foundation works | PASS | Native pointer drag and splitter keyboard resize. |
| AC-WIN-P02-010 | pane minimum constraints enforced | PASS | Rust unit test plus native Home=280 px and End=520 px evidence. |
| AC-WIN-P02-011 | Light theme implemented | PASS | Semantic tokens and native Light screenshot. |
| AC-WIN-P02-012 | Dark theme implemented | PASS | Semantic tokens and native Dark screenshot. |
| AC-WIN-P02-013 | System theme implemented | PASS | Typed preference, CSS media-query path, initial native System state. |
| AC-WIN-P02-014 | semantic theme tokens used | PASS | Centralized token block in `styles.css`; no theme framework added. |
| AC-WIN-P02-015 | Persian RTL fixture renders correctly | PASS | Native Persian fixture screenshot/accessibility text. |
| AC-WIN-P02-016 | English LTR fixture renders correctly | PASS | English shell/placeholder labels and document-placeholder fixture. |
| AC-WIN-P02-017 | mixed RTL/LTR fixture renders correctly | PASS | Native mixed fixture with Persian, `cargo test`, `0.1.0`, and `Windows`. |
| AC-WIN-P02-018 | application root is not globally forced RTL | PASS | `index.html` and root `<main>` are explicitly LTR; static validator. |
| AC-WIN-P02-019 | CSS logical properties used appropriately | PASS | Direction-sensitive spacing/borders use logical CSS properties. |
| AC-WIN-P02-020 | keyboard traversal works | PASS | Native Tab, Shift+Tab, select controls, and splitter keyboard checks. |
| AC-WIN-P02-021 | visible focus states exist | PASS | Native blue focus outline on mode controls/splitter and CSS `:focus-visible`. |
| AC-WIN-P02-022 | semantic controls/accessibility labels present | PASS | Native accessibility tree names buttons, tabs, combos, pane, splitter, and landmarks. |
| AC-WIN-P02-023 | narrow-window layout usable | PASS | 960×640 configured standard window; 962×671 native view with side pane and no overlap. |
| AC-WIN-P02-024 | medium-window layout usable | PASS | Native release run at 1286×794 logical pixels (origin 2,8); toolbar, mode switch, workspace, AI sidebar, splitter drag, Persian/mixed fixtures, no overlap, and visible splitter focus inspected. |
| AC-WIN-P02-025 | large-window layout usable | PASS | Native maximize evidence: 1536×816 screenshot with side pane and readable controls. |
| AC-WIN-P02-026 | minimum window size defined/tested | PASS | Tauri `minWidth=900`, `minHeight=600`; static validator. |
| AC-WIN-P02-027 | 100% DPI validation | PASS | Fixed production release run at live `WebView scale 100%`; `962×672` native screenshot, visible toolbar/labels, usable modes/sidebar/splitter, Persian and mixed RTL/LTR fixtures, focus outline, and `902×632` minimum-window evidence. |
| AC-WIN-P02-028 | 125% DPI validation | PASS | Native status reports `WebView scale 125%`; standard and maximized screenshots. |
| AC-WIN-P02-029 | 150% DPI validation | PASS | Current production release run at live `WebView scale 150%`; `963×671` standard and `903×632` minimum native screenshots, readable toolbar/labels, modes/sidebar/splitter, Persian and mixed RTL/LTR fixtures, visible focus, and clean exit. |
| AC-WIN-P02-030 | 200% DPI validation | PASS | Current production release run at live `WebView scale 200%`; native window id 67176, visible `955×540` logical-pixel capture, readable toolbar/labels, usable Preview/Editor/Source, AI sidebar, splitter drag/keyboard resize, Persian/mixed RTL-LTR fixtures, visible focus, no-overlap layout, host-constrained minimum viewport, and clean exit. |
| AC-WIN-P02-031 | Tauri security permissions not broadened unnecessarily | PASS | Exact capability allowlist checked by `validate-phase2.ps1`. |
| AC-WIN-P02-032 | CSP remains restrictive | PASS | Phase 2 and Phase 1 security validators pass; no remote/CSP broadening. |
| AC-WIN-P02-033 | no remote runtime assets | PASS | Static validator scans HTML/CSS and passes; fonts are local. |
| AC-WIN-P02-034 | fmt passes | PASS | `cargo fmt --all -- --check`. |
| AC-WIN-P02-035 | check passes | PASS | `cargo check --workspace`. |
| AC-WIN-P02-036 | clippy -D warnings passes | PASS | `cargo clippy --workspace --all-targets --all-features -- -D warnings`. |
| AC-WIN-P02-037 | workspace tests pass | PASS | 10 Rust tests passed, 0 failed. |
| AC-WIN-P02-038 | Leptos/WASM production build passes | PASS | Local Trunk `build --release`. |
| AC-WIN-P02-039 | native Tauri build passes | PASS | Local `cargo-tauri build --no-bundle --ci`. |
| AC-WIN-P02-040 | native Windows launch passes | PASS | Fixed release executable launched, rendered the WebView2 shell, and exited cleanly. |
| AC-WIN-P02-041 | Light/Dark native evidence recorded | PASS | Textual evidence under `.artifacts/windows-phase2/`; screenshots inspected live. |
| AC-WIN-P02-042 | Persian/mixed-direction native evidence recorded | PASS | Persian and mixed fixture states inspected in native WebView2. |
| AC-WIN-P02-043 | keyboard native evidence recorded | PASS | Tab/Shift+Tab, splitter Right/Home/End, and visible focus inspected. |
| AC-WIN-P02-044 | no Phase 3 document lifecycle implemented | PASS | Production scan and source review; no filesystem/document lifecycle types or permissions. |
| AC-WIN-P02-045 | macOS source preserved | PASS | Final diff scoped to Windows/docs/OKF; no `MarkView/` changes. |
| AC-WIN-P02-046 | Phase 2 docs created | PASS | This matrix, implementation, and evidence files exist. |
| AC-WIN-P02-047 | OKF updated | PASS | Windows architecture, component/view concepts, and indexes updated. |
| AC-WIN-P02-048 | OKF/log.md updated | PASS | 2026-08-19 Phase 2 knowledge entry. |
| AC-WIN-P02-049 | HANDOFF updated | PASS | Root handoff records final state, tests, evidence, and limits. |
| AC-WIN-P02-050 | final Git state recorded | PASS | Final status/diff inspection recorded in `HANDOFF.md`. |
| AC-WIN-P02-051 | Phase 3 readiness determined | PASS | Explicitly `PHASE_3_READINESS = READY` after all 51 Phase 2 criteria reconciled to PASS; Phase 3 was not started. |

## Final reconciliation

All 51 Phase 2 acceptance criteria are PASS:
`PASS: 51 | FAIL: 0 | PARTIAL: 0 | BLOCKED: 0 | OPEN: 0`.

Phase 3 was not started. A separate user-authorized prompt is required before
any Phase 3 work begins.
