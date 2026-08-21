# Project Handoff

## Last Updated

2026-08-21

## Project Summary

Markowski is a native macOS SwiftUI Markdown application documented under
`OKF/`. The repository also contains the production Windows Rust/Tauri 2 /
Leptos/WebView2 workspace under `windows/`. Phase 3 adds filesystem-backed
Markdown/Mermaid document lifecycle and safety while preserving the macOS
source tree.

## Current Objective

Complete the authorized Windows Phase 3 document lifecycle and filesystem
safety work. Do not start Phase 4 Source Editor, Phase 5 Preview/Mermaid, or
Phase 8 persistence without a separate prompt.

## Current Phase or Milestone

`PHASE_STATUS = PARTIAL`
`PHASE_4_READINESS = NOT_READY`

The domain/platform/shell/UI implementation, automated filesystem matrix,
security/CI validators, and tracked documentation are in place. Native release
frontend/Tauri packaging and manual lifecycle evidence remain open because the
local sandbox denies nested `cargo metadata` launched by Trunk/Tauri CLI; the
requested escalated retry was rejected by the environment usage limit.

## Repository State

- Repository path: `D:\All projects\markowski`
- Current branch: `main`
- Base or starting commit: `e208cb91ad3e6961e3c6f382927fdb38d470882f`
- Current HEAD: `e208cb91ad3e6961e3c6f382927fdb38d470882f`
- HEAD summary: `docs(windows): complete Phase 2 DPI validation`
- Working tree status: uncommitted Windows Phase 3 implementation, docs,
  workflow, OKF updates, and handoff changes; no pre-existing clean-tree
  changes were present at task start.
- Staged changes: none.
- Unstaged changes: tracked Windows/OKF/docs/workflow files listed below.
- Untracked files: new Phase 3 crates, tests, docs, OKF concepts, and the
  Phase 3 validator listed below. Ignored `.artifacts/windows-phase3/` contains
  a checkpoint note.

## Completed Work

- Added `markowski-document` with typed errors, absolute `.md`/`.mmd` path
  validation, UTF-8/BOM and newline policy, content/disk SHA-256 revisions,
  dirty/conflict/missing/rename states, revision-bound save attempts, reload,
  and filesystem-independent coordination.
- Added `markowski-platform-windows` with stable reads, same-directory flushed
  temporary writes, Windows `MoveFileExW` replacement, final hash verification,
  native Unicode file dialogs, and 250 ms `notify` watcher coalescing.
- Added typed Tauri document commands and backend dirty-switch protection,
  native dirty-close Save/Discard/Cancel handling, watcher event emission, and
  serialized document access.
- Replaced Phase 2 New/Open placeholders with a minimal lifecycle textarea,
  typed state polling, debounced updates, persisted-path autosave, visible
  lifecycle status, visible Reload, and explicit conflict-safe UI behavior.
  Preview, Source Editor, Mermaid rendering, AI, and persistence remain out
  of scope.
- Added the real temporary-file T1–T20 integration matrix plus external
  watcher and own-save regression tests.
- Added Phase 3 security/scope/CI validators and updated the workflow, README,
  security notes, e2e boundary notes, canonical OKF, Phase 3 docs, and this
  handoff.

## Work in Progress

- Native release frontend and Tauri build/launch evidence is blocked by the
  local nested-process restriction described above.
- Long-path dialog behavior, ACL-specific permission behavior, and full native
  New/Open/Save/Reload/conflict/Persian lifecycle inspection are not yet
  evidenced.

## Remaining Work

- Obtain a permitted environment/run for `trunk build --release` and
  `cargo tauri build --no-bundle --ci`.
- Launch the resulting release executable and record native lifecycle, watcher,
  stale-overwrite, delete/rename, Unicode/Persian, autosave, long-path, and
  dirty-close evidence under ignored `.artifacts/windows-phase3/`.
- Rerun final gates after any build/evidence-only changes, update the Phase 3
  acceptance matrix/evidence, and decide whether status can become `COMPLETE`.
- If a real recurring lock/replacement lesson is needed, append it to
  `D:\All projects\Mistakes\mistakes.md` when write access is available. The
  log was reviewed but the attempted append was rejected by the environment
  usage limit; no replacement log was created.

## Exact Next Steps

1. Start from this handoff; do not redo the completed domain or T1–T20 work.
2. Run the native release commands in a permitted Windows environment.
3. Inspect the real WebView2 app and record only observed results.
4. Update `docs/windows/phase-03/ACCEPTANCE_MATRIX.md`, `EVIDENCE.md`, OKF
   status/log, and this handoff.
5. Run `git diff --check`, final status, and all relevant gates; report
   `COMPLETE` only if no required native/data-loss criterion remains open.

## Files Created

- `docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md`
- `docs/windows/phase-03/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-03/EVIDENCE.md`
- `OKF/architecture/windows-document-lifecycle.md`
- `OKF/components/windows-document-lifecycle.md`
- `OKF/components/windows-platform-filesystem.md`
- `windows/crates/markowski-document/Cargo.toml`
- `windows/crates/markowski-document/src/lib.rs`
- `windows/crates/markowski-platform-windows/Cargo.toml`
- `windows/crates/markowski-platform-windows/src/lib.rs`
- `windows/crates/markowski-platform-windows/tests/document_lifecycle.rs`
- `windows/scripts/validate-phase3.ps1`
- `.artifacts/windows-phase3/checkpoint.md` (ignored)

## Files Modified

- `.github/workflows/windows-phase1.yml`
- `OKF/index.md`, `OKF/architecture/index.md`,
  `OKF/architecture/windows-architecture.md`, `OKF/components/index.md`,
  `OKF/components/windows-shell.md`, and `OKF/log.md`
- `windows/Cargo.toml`, `windows/Cargo.lock`, `windows/README.md`,
  `windows/SECURITY_CHECKS.md`
- `windows/apps/desktop-shell/Cargo.toml` and `src/lib.rs`
- `windows/apps/desktop-ui/Cargo.toml`, `src/app.rs`, `src/state.rs`, and
  `styles.css`
- `windows/scripts/validate-ci.ps1`, `validate-phase2.ps1`,
  `validate-security.ps1`
- `windows/tests/e2e/README.md`
- `HANDOFF.md`

## Important Architecture and Design Decisions

- `windows/crates/markowski-document` is platform-neutral and has no Tauri,
  Win32, WebView, HTTP, or direct filesystem authority.
- `windows/crates/markowski-platform-windows` is the only filesystem/native
  dialog boundary. It performs a pre-write expected-disk comparison twice,
  writes a flushed same-directory temp, atomically replaces, then verifies the
  final hash. A remaining OS-level race after the last comparison is a known
  limitation; no silent overwrite is accepted by the deterministic model/tests.
- Save proposals carry a memory generation; an edit during save leaves the
  newer revision dirty. `AppState` serializes commands and the UI autosave
  skips known conflict/missing/rename/saving states.
- External events trigger a disk reconciliation, not an unconditional reload.
  Dirty external edits become `Conflict`; clean external edits become
  `ExternalChanged`; delete/rename preserve memory.
- New/Open requires explicit discard confirmation in the UI and a typed
  backend `discard_changes` flag. Untitled documents never autosave to a hidden
  path. Dirty window close uses a native Save/Discard/Cancel prompt.
- The Phase 3 UI is a deliberately plain, replaceable textarea. No Phase 4
  editor architecture, Phase 5 renderer, or Phase 8 database/settings path was
  added.
- Existing macOS `MarkView/`, `MarkViewTests/`, and `MarkView.xcodeproj/` were
  not modified.

## Commands Executed

From `windows/`:

- `cargo fmt --all -- --check` (baseline and final)
- `cargo fmt --all`
- `cargo check --workspace` (baseline and final)
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`
  (baseline and final)
- `cargo test --workspace` (baseline and final)
- `cargo test -p markowski-platform-windows`
- `cargo build --target wasm32-unknown-unknown --release -p markowski-desktop-ui`
  (baseline/final and post-Reload UI change)
- `cargo build --release -p markowski-desktop-shell`
- `scripts/validate-security.ps1`
- `scripts/validate-phase2.ps1`
- `scripts/validate-phase3.ps1`
- `scripts/validate-ci.ps1`
- `git diff --check`, Git status/diff inspections

Release attempts:

- `trunk build --release` failed with `Access is denied` while Trunk spawned
  `cargo metadata`; direct `cargo metadata --no-deps --format-version 1` passed.
- `cargo tauri build --no-bundle --ci` failed at the same nested `cargo
  metadata` step. An escalated retry was rejected by the environment usage
  limit, and no workaround was used.

## Validation and Test Results

- Final Rust fmt: PASS.
- Final workspace check: PASS; only the existing `proc-macro-error2`
  future-incompatibility advisory was reported.
- Final strict Clippy: PASS with warnings denied.
- Final workspace tests: PASS; 3 core + 4 shell + 4 UI + 10 document domain +
  4 platform unit + 1 platform integration tests, 0 failures; doc-tests had
  no tests.
- Platform filesystem test suite: PASS; watcher tests and T1–T20 matrix pass.
- Direct release WASM compilation: PASS.
- Direct release shell compilation: PASS; this is not a claim that the Tauri
  CLI packaging/build hook passed.
- Security, Phase 2 regression, Phase 3 scope, and CI contract validators:
  PASS.
- Trunk/Tauri release packaging and native Phase 3 launch: NOT RUN/PASS;
  blocked at metadata process creation.

## Known Issues and Blockers

- Native release/manual evidence is the primary blocker for `COMPLETE` and
  `PHASE_4_READINESS=READY`.
- The native dialog uses a large UTF-16 buffer and wide Win32 paths, but every
  Windows long-path policy and dialog edge case still needs host evidence.
- The filesystem adapter closes the normal stale-save window with repeated
  compare-and-verify checks, but it does not provide a kernel-level
  compare-and-swap guarantee against a hostile writer that races exactly after
  the final comparison.
- Hosted GitHub Actions, cargo-audit, and native WebDriver are not claimed.

## Database or Migration State

Not applicable. No database, migration, SQLite, or durable document storage was
added. Markdown files remain authoritative.

## Configuration and Environment Notes

- Windows host uses the repository `rust-toolchain.toml`, MSVC, WebView2, and
  `wasm32-unknown-unknown`; direct release compilation succeeded locally.
- `NO_COLOR=false` was set for build attempts because the inherited environment
  can make Trunk's boolean parser reject a build hook.
- Native packaging requires a permitted process environment for Trunk/Tauri
  child `cargo metadata` calls.

## Uncommitted or Partially Applied Changes

All Phase 3 source, tests, docs, OKF, workflow, and handoff changes are
uncommitted by design. No files are staged. The failed range-lock experiment
was fully removed; current tests pass against the final two-compare atomic
implementation.

## Recovery or Rollback Notes

Do not reset or discard the working tree. To review the implementation, start
with this file, `OKF/index.md`, and
`docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md`. If native validation must
be deferred, leave the source/tests/docs as-is and preserve the `PARTIAL`
status. No commit or branch was created.

## Related Documentation

- `AGENTS.md`
- `OKF/index.md`
- `OKF/architecture/windows-document-lifecycle.md`
- `docs/windows/phase-03/PHASE_03_IMPLEMENTATION.md`
- `docs/windows/phase-03/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-03/EVIDENCE.md`
- `windows/README.md`
- `windows/SECURITY_CHECKS.md`

## Notes for the Next Agent

The implementation is substantially complete but the phase is intentionally
not closed. Do not report native build/launch or Phase 4 readiness from the
direct Rust compilation alone. Run the native release path in an environment
where Trunk/Tauri can spawn Cargo, inspect the actual WebView2 UI, collect
evidence, then reconcile the matrix and handoff before stopping.
