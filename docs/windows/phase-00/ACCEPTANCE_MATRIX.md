# Phase 0 Acceptance Matrix

Status values are `OPEN`, `PASS`, `FAIL`, `PARTIAL`, `DEFERRED`, `BLOCKED`, and
`N/A`. A mandatory `BLOCKED` or `FAIL` prevents Phase 0 from being declared
`COMPLETE` and prevents Phase 1 readiness.

| ID | Acceptance criterion | Evidence / owner | Status |
| --- | --- | --- | --- |
| AC-WIN-P00-001 | Git branch, HEAD, baseline status, remote, and uncommitted work recorded | `PHASE_00_BASELINE_AUDIT.md`, `EVIDENCE.md` | PASS |
| AC-WIN-P00-002 | Master plan read and Phase 0 scope/forbidden work captured | Master plan; baseline audit | PASS |
| AC-WIN-P00-003 | Existing OKF v0.2 bundle and relevant concepts read | `OKF/index.md`, architecture concepts | PASS |
| AC-WIN-P00-004 | macOS document lifecycle and file safety audited | Baseline audit; source references | PASS |
| AC-WIN-P00-005 | Renderer/Markdown/Mermaid behavior and assets audited | Baseline audit; fixture inventory | PASS |
| AC-WIN-P00-006 | Visual editor/source fidelity behavior audited | Baseline audit; editor source references | PASS |
| AC-WIN-P00-007 | Navigation/search/reference behavior audited | Baseline audit; parity IDs | PASS |
| AC-WIN-P00-008 | AI registry/providers/models/stream/cancel/usage/reasoning audited | Baseline audit; parity IDs | PASS |
| AC-WIN-P00-009 | Attachments, chat persistence, and document extraction audited | Baseline audit; tests inventory | PASS |
| AC-WIN-P00-010 | AI operations/diff/review/apply/discard/undo/revert/stale handling audited | Baseline audit; risk R-WIN-003 | PASS |
| AC-WIN-P00-011 | Persian/RTL/mixed-direction behavior and test gap recorded | Baseline audit; PAR-UX IDs | PASS |
| AC-WIN-P00-012 | Traceable feature parity matrix contains stable IDs and phase ownership | `FEATURE_PARITY_MATRIX.md` | PASS |
| AC-WIN-P00-013 | Windows Rust/Tauri/Leptos/WebView2 layered architecture documented | `WINDOWS_ARCHITECTURE.md` | PASS |
| AC-WIN-P00-014 | IPC, capability, renderer, file, and platform boundaries are explicit | Architecture/security docs | PASS |
| AC-WIN-P00-015 | Document safety, save, conflict, hash, and persistence contracts documented | Architecture/security docs | PASS |
| AC-WIN-P00-016 | Threat model and security controls include AI, WebView2, secrets, paths, and logs | `WINDOWS_SECURITY_MODEL.md` | PASS |
| AC-WIN-P00-017 | Test pyramid, fixtures, CI lanes, and native E2E strategy documented | `WINDOWS_TEST_STRATEGY.md` | PASS |
| AC-WIN-P00-018 | Windows x64/ARM64/Windows 10/32-bit support policy recorded | `WINDOWS_SUPPORT_MATRIX.md` | PASS |
| AC-WIN-P00-019 | ADR-WIN-001 through ADR-WIN-012 exist with required fields | `adrs/` and decision register | PASS |
| AC-WIN-P00-020 | Disposable Tauri + Leptos smoke project compiles and starts | `EVIDENCE.md` — final remediation: release WASM build, native `.exe`, and clean close | PASS |
| AC-WIN-P00-021 | Native Windows launch and typed IPC evidence exists | `EVIDENCE.md` — final remediation: WebView2 window and `native-rust-bridge-ok` response | PASS |
| AC-WIN-P00-022 | Current Windows host/toolchain/WebView2 evidence is captured | `EVIDENCE.md` remediation checkpoint | PASS |
| AC-WIN-P00-023 | No Phase 1 production UI/features/provider/workspace were implemented | Git diff and forbidden-scope search | PASS |
| AC-WIN-P00-024 | macOS source and Xcode project remain untouched | Git diff path inspection | PASS |
| AC-WIN-P00-025 | OKF v0.2 Windows knowledge concept and log entry are current | `OKF/architecture/windows-architecture.md`, `OKF/log.md` | PASS |
| AC-WIN-P00-026 | Root HANDOFF records the real state, blockers, and next action | `HANDOFF.md` | PASS |
| AC-WIN-P00-027 | Documentation/frontmatter/links/diff whitespace checks pass | `EVIDENCE.md` final validation | PASS |
| AC-WIN-P00-028 | Phase status and Phase 1 readiness are explicitly reported | Final report and handoff | PASS |

## Gate interpretation

Current Phase 0 status is `COMPLETE`. The final remediation verified the
existing smoke project’s release WASM build, native Windows `.exe` build,
WebView2 launch, typed IPC response, clean close, and required security checks.
The mandatory matrix is `PASS: 28`, `BLOCKED: 0`, `FAIL: 0`, `PARTIAL: 0`,
`OPEN: 0`. Phase 1 readiness is `READY`; no Phase 1 implementation was
started.
