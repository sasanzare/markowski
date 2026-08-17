# Windows Phase 1 acceptance matrix

Phase 1 is evaluated only against the criteria authorized by the execution
prompt. `PASS` means that the criterion has local evidence in
[`EVIDENCE.md`](EVIDENCE.md) or in the referenced production source.

| ID | Criterion | Status | Evidence |
| --- | --- | --- | --- |
| AC-WIN-P01-001 | Git baseline recorded | PASS | [`EVIDENCE.md`](EVIDENCE.md), Git baseline |
| AC-WIN-P01-002 | Production `windows/` root created | PASS | [`PHASE_01_IMPLEMENTATION.md`](PHASE_01_IMPLEMENTATION.md) |
| AC-WIN-P01-003 | macOS project not moved | PASS | Git status scoped to `MarkView/`, `MarkViewTests/`, and `MarkView.xcodeproj/` |
| AC-WIN-P01-004 | Rust workspace created | PASS | `windows/Cargo.toml` and three workspace members |
| AC-WIN-P01-005 | `Cargo.lock` committed to working tree | PASS | `windows/Cargo.lock` exists; no Git commit was made by policy |
| AC-WIN-P01-006 | Rust toolchain pinned | PASS | `windows/rust-toolchain.toml`; Rust 1.97.1 MSVC, MSVC and WASM targets, rustfmt, clippy |
| AC-WIN-P01-007 | Leptos production UI foundation created | PASS | `windows/apps/desktop-ui/`; release Trunk build passed |
| AC-WIN-P01-008 | Tauri production shell created | PASS | `windows/apps/desktop-shell/`; release Tauri build passed |
| AC-WIN-P01-009 | Typed IPC baseline implemented | PASS | `get_app_info` request/response in `markowski-core` and shell command |
| AC-WIN-P01-010 | Error foundation implemented | PASS | Typed `CoreError`, `IpcError`, and `ShellError` boundaries |
| AC-WIN-P01-011 | Structured local logging implemented | PASS | `desktop-shell/src/lib.rs`; startup fields and environment filter |
| AC-WIN-P01-012 | Least-privilege Tauri capabilities configured | PASS | `capabilities/default.json` and command-specific permission |
| AC-WIN-P01-013 | Restrictive CSP configured | PASS | `tauri.conf.json`; local self/WASM/IPC directives only |
| AC-WIN-P01-014 | `fmt` passes | PASS | `cargo fmt --check` exit 0 |
| AC-WIN-P01-015 | `check` passes | PASS | `cargo check --workspace` exit 0 |
| AC-WIN-P01-016 | Clippy with `-D warnings` passes | PASS | Canonical workspace clippy command exit 0 |
| AC-WIN-P01-017 | Workspace tests pass | PASS | `cargo test --workspace`; 6 unit tests passed, 0 failed |
| AC-WIN-P01-018 | WASM/Leptos production build passes | PASS | `trunk build --release` exit 0 |
| AC-WIN-P01-019 | Native Tauri build passes | PASS | `cargo-tauri build --no-bundle --ci` exit 0 |
| AC-WIN-P01-020 | Production Windows executable launches | PASS | Production executable launched through WebView2 on the current host |
| AC-WIN-P01-021 | Production typed IPC runtime verified | PASS | UI displayed `Native bridge connected`, version `0.1.0`, platform `windows` |
| AC-WIN-P01-022 | Windows CI workflow created | PASS | `.github/workflows/windows-phase1.yml` |
| AC-WIN-P01-023 | CI workflow configuration validated | PASS | `scripts/validate-ci.ps1` exit 0; hosted run was not dispatched |
| AC-WIN-P01-024 | No Phase 2 product features implemented | PASS | Minimal source review and explicit out-of-scope record |
| AC-WIN-P01-025 | macOS source preserved | PASS | No macOS source or project-file changes in final status |
| AC-WIN-P01-026 | Phase 1 docs created | PASS | `docs/windows/phase-01/` contains implementation, evidence, and matrix |
| AC-WIN-P01-027 | OKF updated | PASS | Windows architecture, root index, and architecture index updated |
| AC-WIN-P01-028 | `OKF/log.md` updated | PASS | 2026-08-17 Phase 1 entry |
| AC-WIN-P01-029 | HANDOFF updated | PASS | Root `HANDOFF.md` records final Phase 1 state |
| AC-WIN-P01-030 | Final Git state recorded | PASS | Final status and diff checks recorded in HANDOFF/evidence |
| AC-WIN-P01-031 | Phase 2 readiness determined | PASS | `PHASE_2_READINESS = READY`; Phase 2 was not started |

## Summary

```text
PASS: 31
FAIL: 0
PARTIAL: 0
BLOCKED: 0
NOT RUN: 0 (mandatory acceptance criteria)
PHASE_STATUS = COMPLETE
PHASE_2_READINESS = READY
```

Remote GitHub Actions execution and `cargo audit` remain explicitly recorded
as not run; neither is a separate mandatory acceptance row in this Phase 1
prompt, and no remote or audit pass is claimed.
