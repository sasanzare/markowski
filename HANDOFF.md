# Project Handoff

## Last Updated

2026-08-17

## Project Summary

Markowski is a native macOS SwiftUI Markdown and Mermaid editor with Preview,
Editor, and Source modes, local document persistence, navigation/search, Persian
and RTL support, and an optional multi-provider AI assistant. The repository is
organized under the `MarkView` source target and documents the macOS baseline in
`OKF/`.

## Current Objective

Complete the bounded Phase 0 remediation from
`docs/windows/MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`: retain the verified
Windows prerequisites and the existing disposable Tauri 2 + Leptos smoke
evidence, while keeping Phase 1 and a production Windows workspace out of
scope.

## Current Phase or Milestone

Phase 0 remediation completed on 2026-08-17. The Windows identity and native
prerequisites are verified, and the existing disposable Leptos/Tauri scaffold
plus typed bridge remain under the ignored `.artifacts/` directory. Crates.io
connectivity was verified, Tauri CLI `2.11.4` is installed in the dedicated D:
Cargo home, the release WASM and native `.exe` builds succeeded, and the
executable opened in WebView2, returned `native-rust-bridge-ok` through typed
IPC, and closed cleanly. Acceptance summary: `PASS 28`, `BLOCKED 0`, `FAIL 0`,
`PARTIAL 0`, `OPEN 0`. Phase 1 was not started.

## Repository State

- Repository path: `D:\All projects\markowski`
- Current branch: `main`
- Base or starting commit: `7d85b84c55f64636c69e746c37e98781182459c5`
- Current HEAD: `7d85b84c55f64636c69e746c37e98781182459c5`
- Working tree status: pre-existing Phase 0 documentation and `.gitignore`
  changes remain unstaged; the ignored smoke/evidence artifacts are outside
  Git tracking.
- Staged changes: None.
- Unstaged changes: Phase 0 documentation work and `.gitignore` update.
- Untracked files: `docs/windows/` and the new Phase 0 documents; this file is also new.

## Completed Work

- Read repository instructions, the master plan, README, release notes, the
  existing OKF bundle, relevant architecture/component/view concepts, and the
  persistent mistakes log.
- Audited the macOS document lifecycle, renderer, Markdown model/parser/
  serializer, visual editor, navigation, AI providers and operations, chat and
  attachments, persistence, keychain behavior, Persian/RTL handling, tests, and
  fixture assets.
- Audited the Windows environment and recorded the toolchain/runtime gaps.
- Re-verified the remediation environment: Windows 11 25H2 x64 is established
  by Microsoft’s build mapping (`26200.8875`), Rust MSVC `1.87.0` is active,
  Visual Studio Build Tools 18.9 is installed, `cl.exe`/`link.exe` resolve, the
  Windows SDK is `10.0.26100.0`, and WebView2 is `151.0.4129.86`.
- Reviewed official Tauri, WebView2, Windows Credential Manager, and OKF sources
  for the Phase 0 evidence and testing strategy.
- Added the required Phase 0 documents under `docs/windows/phase-00/`, including
  the parity matrix, architecture/security/test/support strategy, decision/risk/
  acceptance registers, evidence log, and ADR-WIN-001 through ADR-WIN-012.
- Added the proposed Windows architecture concept to the existing OKF v0.2
  bundle and recorded the documentation change in `OKF/log.md`.
- Added `.artifacts/` to `.gitignore`; no disposable artifact was generated.
- Created the official `create-tauri-app@4.6.2` Leptos/Tauri 2 scaffold at
  `.artifacts/windows-phase0/tauri-leptos-smoke/`.
- Replaced the template greeting with a minimal typed `phase0_smoke` command,
  a `native-rust-bridge-ok` response, a narrow capability set, and a restrictive
  smoke CSP. This is disposable artifact code only.
- Added the `wasm32-unknown-unknown` target.
- Prepared `D:\All projects\.cargo-markowski` as the remediation Cargo home,
  copied the existing registry cache there without modifying the user’s Rust
  installation, and installed Trunk `0.21.14` at
  `D:\All projects\.cargo-markowski\bin\trunk.exe`.
- An initial offline smoke attempt stopped at missing cached Tauri crates and
  an initial offline Tauri CLI install was unavailable; after connectivity was
  restored, the existing smoke was resumed without recreation.
- Verified crates.io DNS/TCP reachability and Cargo registry access, installed
  Tauri CLI `2.11.4`, and retained Trunk `0.21.14` in
  `D:\All projects\.cargo-markowski`.
- Pinned only MSRV-sensitive disposable-smoke transitive dependencies for the
  verified Rust `1.87.0` host.
- Built release WASM with Trunk and a real native release executable with
  `cargo-tauri build --no-bundle --ci`.
- Launched the produced executable, verified the WebView2 window and typed
  `phase0_smoke` response `native-rust-bridge-ok`, closed it cleanly, and ran
  the required static security checks.

## Work in Progress

None. The final Phase 0 build, launch, IPC, close, and security checks are
complete; no Phase 1 work has started.

## Remaining Work

No mandatory Phase 0 work remains. Any installer-bundle follow-up is optional
and is not required by the Phase 0 executable gate. Phase 1 remains a separate
scope and requires an explicit request.

## Exact Next Steps

1. Preserve the final evidence under `.artifacts/windows-phase0/` and the
   updated Phase 0 documentation.
2. Do not create a production `windows/` workspace or start Phase 1 without a
   separate explicit request.

## Files Created

- `docs/windows/phase-00/PHASE_00_BASELINE_AUDIT.md`
- `docs/windows/phase-00/FEATURE_PARITY_MATRIX.md`
- `docs/windows/phase-00/WINDOWS_ARCHITECTURE.md`
- `docs/windows/phase-00/WINDOWS_SECURITY_MODEL.md`
- `docs/windows/phase-00/WINDOWS_TEST_STRATEGY.md`
- `docs/windows/phase-00/WINDOWS_SUPPORT_MATRIX.md`
- `docs/windows/phase-00/DECISION_REGISTER.md`
- `docs/windows/phase-00/RISK_REGISTER.md`
- `docs/windows/phase-00/ACCEPTANCE_MATRIX.md`
- `docs/windows/phase-00/EVIDENCE.md`
- `docs/windows/phase-00/adrs/ADR-WIN-001` through `ADR-WIN-012`
- `OKF/architecture/windows-architecture.md`
- `HANDOFF.md`
- Ignored disposable scaffold: `.artifacts/windows-phase0/tauri-leptos-smoke/`
- Ignored remediation evidence: `.artifacts/windows-phase0/FINAL_EVIDENCE.md`

## Files Modified

- `.gitignore` — ignore `.artifacts/` as required for disposable evidence.
- `OKF/index.md`, `OKF/architecture/index.md`, `OKF/log.md` — link and record
  the Windows knowledge extension.
- `docs/windows/phase-00/EVIDENCE.md` and `ACCEPTANCE_MATRIX.md` — record the
  final native build/launch evidence and the 28-pass matrix.
- `HANDOFF.md` — this final Phase 0 checkpoint.
- `OKF/architecture/windows-architecture.md` — current disposable-smoke
  feasibility state.
- Ignored smoke files modified: `Cargo.toml`, `src/app.rs`,
  `src-tauri/src/lib.rs`, `src-tauri/build.rs`, `src-tauri/Cargo.toml`,
  `src-tauri/capabilities/default.json`, `src-tauri/tauri.conf.json`, and
  `index.html` under `.artifacts/windows-phase0/tauri-leptos-smoke/`.

## Important Architecture and Design Decisions

The product invariant is plain Markdown source as the document authority,
local-first operation, optional AI, and explicit proposal review before any AI
edit. The Windows design must keep domain/core crates independent from Tauri,
WebView2, filesystem, HTTP, and Windows APIs. Windows secrets must use the
Windows Credential Manager with no Base64/UserDefaults fallback.

## Commands Executed

See `docs/windows/phase-00/EVIDENCE.md` and
`.artifacts/windows-phase0/FINAL_EVIDENCE.md` for the bounded audit and
remediation commands/results. Connectivity, Tauri CLI `2.11.4`, Trunk
`0.21.14`, release WASM build, native `cargo-tauri build --no-bundle --ci`,
native launch, typed IPC, clean close, and static security scans all passed.
The persistent mistakes log was reviewed and updated with the reusable Tauri
ACL and inherited `NO_COLOR` lessons. No migration, commit, or push was
performed.

## Validation and Test Results

The macOS Xcode toolchain is not available in this Windows environment, so macOS
build/tests were not run. The final Windows smoke validation passed: release
WASM built, native `.exe` linked, WebView2 rendered the smoke UI, typed IPC
returned `native-rust-bridge-ok`, and the application closed cleanly. Static
security checks passed: no credential-like matches, no external script tags, no
shell/filesystem/process capability, and a scoped CSP. Phase 0 is `COMPLETE`;
Phase 1 is `READY` but was not started.

## Known Issues and Blockers

- The optional bundled `cargo-tauri build --ci` path previously failed while
  downloading an NSIS helper; the required executable build passed with
  `--no-bundle`, so this is not a Phase 0 blocker.
- The disposable smoke pins MSRV-sensitive transitive dependencies for Rust
  `1.87.0`; these pins are scoped to the ignored smoke and are not production
  dependency policy.
- The production repository contains no Tauri/Leptos/Cargo workspace; only the
  ignored disposable smoke exists.
- Registry `ProductName=Windows 10 Home` remains stale/contradictory metadata,
  but Microsoft release mapping resolves build `26200.8875` + `25H2` as Windows
  11 25H2 x64 for this remediation checkpoint.
- The macOS baseline has known safety variances that Phase 0 documents but does
  not change: Keychain failure falls back to Base64 in UserDefaults; renderer
  CSP is not observed and Mermaid uses `securityLevel: loose`; proposal conflict
  checks compare disk state but not necessarily unsaved in-memory edits.

## Risks and Assumptions

The production Windows architecture remains a proposal even though its
disposable Tauri/Leptos feasibility smoke now compiles and launches. The native
evidence is limited to the smoke surface and does not claim production parity.
Existing untracked master-plan work is preserved.

## Database or Migration State

Not applicable. No database or migration was changed.

## Configuration and Environment Notes

The remediation environment includes Rust `1.87.0` MSVC active/default,
Visual Studio Build Tools `18.9.0`, `cl.exe` 19.51.36256, `link.exe`, Windows
SDK `10.0.26100.0`, WebView2 Runtime `151.0.4129.86`, Node `24.17.0`, and the
`wasm32-unknown-unknown` target. Remediation tooling uses
`CARGO_HOME=D:\All projects\.cargo-markowski`; Trunk `0.21.14` and Tauri CLI
`2.11.4` are installed there. The smoke build uses
`CARGO_TARGET_DIR=D:\All projects\.cargo-markowski\target-smoke`. The user’s
`C:\Users\moxfo\.cargo` and Rustup installation were not relocated or deleted.

## Uncommitted or Partially Applied Changes

Phase 0 documentation is applied and remains unstaged. The ignored disposable
smoke is configured and has produced release WASM plus a native executable;
final launch/IPC/close evidence is recorded under `.artifacts/windows-phase0/`.
No production source implementation has been started. The pre-existing
untracked master plan remains preserved.

## Recovery or Rollback Notes

Do not discard the pre-existing untracked
`docs/windows/MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`. The smoke and final
evidence are ignored under `.artifacts/`; all Phase 0 changes remain unstaged.
Do not create a production `windows/` workspace or discard the final smoke
evidence when continuing.

## Related Documentation

- `docs/windows/MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`
- `OKF/index.md`
- `README.md`
- `RELEASE_NOTES.md`

## Notes for the Next Agent

Keep Phase 0 bounded. Do not create a production `windows/` workspace, port
Swift code, add UI, add providers, or start Phase 1 without a separate explicit
request. The native validation is now evidenced only for the existing
disposable smoke; do not generalize it into production parity claims.
