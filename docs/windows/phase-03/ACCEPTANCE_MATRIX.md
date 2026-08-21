# Windows Phase 3 Acceptance Matrix

Status vocabulary: `PASS` means the implementation and the cited local
validation are complete; `PARTIAL` means code exists but a required native or
manual check is still open; `PENDING` means the check has not yet been run.

| ID | Acceptance criterion | Status | Evidence |
| --- | --- | --- | --- |
| AC-WIN-P03-001 | Git baseline recorded | PASS | `EVIDENCE.md`; HEAD `e208cb91ad3e6961e3c6f382927fdb38d470882f` |
| AC-WIN-P03-002 | Phase 2 regression gates pass | PASS | Baseline and final workspace gates |
| AC-WIN-P03-003 | Document domain crate/model implemented | PASS | `markowski-document` crate and unit tests |
| AC-WIN-P03-004 | Windows filesystem boundary implemented | PASS | `markowski-platform-windows` crate |
| AC-WIN-P03-005 | Untitled/New document works | PASS | Domain/shell implementation; native check pending |
| AC-WIN-P03-006 | `.md` open works | PASS | T1 integration test |
| AC-WIN-P03-007 | `.mmd` open works | PASS | T2 integration test |
| AC-WIN-P03-008 | Unsupported extension handled safely | PASS | Domain extension tests |
| AC-WIN-P03-009 | Save works | PASS | T3 and platform tests |
| AC-WIN-P03-010 | First Save As works | PASS | T4 integration test |
| AC-WIN-P03-011 | Subsequent Save As works | PASS | Coordinator Save As path transition test |
| AC-WIN-P03-012 | SHA-256 persisted revision implemented | PASS | Hash model and T18 verification |
| AC-WIN-P03-013 | Dirty state correct | PASS | Domain state tests |
| AC-WIN-P03-014 | Matching save clears the correct dirty revision | PASS | Save completion tests |
| AC-WIN-P03-015 | Edit during save remains dirty | PASS | Domain test and T20 regression |
| AC-WIN-P03-016 | Atomic write strategy implemented | PASS | `write_atomic`, flush, replace, final hash check |
| AC-WIN-P03-017 | Temp file is same-directory/same-volume | PASS | `temp_path` parent enforcement |
| AC-WIN-P03-018 | Write/replace failure preserves memory/original | PASS | T6 integration test |
| AC-WIN-P03-019 | Stale disk overwrite refused | PASS | Domain stale-revision test and T8 |
| AC-WIN-P03-020 | External modification detected | PASS | Coordinator reconciliation and watcher tests |
| AC-WIN-P03-021 | Clean external modification safely reloadable | PASS | T7/T9 integration test |
| AC-WIN-P03-022 | Dirty external modification becomes conflict | PASS | T8 integration test |
| AC-WIN-P03-023 | External delete preserves memory | PASS | T10 integration test |
| AC-WIN-P03-024 | External rename handled safely | PASS | T11 integration test |
| AC-WIN-P03-025 | Own-save watcher events do not create false conflict | PASS | Native watcher regression test |
| AC-WIN-P03-026 | Watcher debounce/coalescing works | PASS | 250 ms watcher implementation and test |
| AC-WIN-P03-027 | Autosave follows approved behavior | PARTIAL | Debounced persisted-path UI autosave implemented; native timing check pending |
| AC-WIN-P03-028 | Autosave does not bypass conflict protection | PASS | UI state guard plus coordinator conflict refusal |
| AC-WIN-P03-029 | Overlapping saves are coordinated | PASS | AppState mutex, `Saving` state, revision-bound attempt |
| AC-WIN-P03-030 | UTF-8 English works | PASS | T1/T3 integration test |
| AC-WIN-P03-031 | UTF-8 Persian works | PASS | T12/T13 integration test |
| AC-WIN-P03-032 | Encoding/BOM policy tested | PASS | BOM integration test and domain tests |
| AC-WIN-P03-033 | LF behavior tested | PASS | T16 and newline unit tests |
| AC-WIN-P03-034 | CRLF behavior tested | PASS | T15 and platform round-trip test |
| AC-WIN-P03-035 | Unicode filename works | PASS | Emoji filename integration test |
| AC-WIN-P03-036 | Persian filename works | PASS | Persian filename integration test |
| AC-WIN-P03-037 | Long-path behavior validated | PARTIAL | Wide path model/dialog buffer implemented; native long-path run pending |
| AC-WIN-P03-038 | Empty file works | PASS | T17 integration test |
| AC-WIN-P03-039 | Large file lifecycle validated | PASS | Deterministic 1 MiB T18 integration test |
| AC-WIN-P03-040 | Permission failure handled safely | PARTIAL | Typed permission mapping and invalid-target test; ACL-specific native run pending |
| AC-WIN-P03-041 | Minimal lifecycle surface without Phase 4 editor work | PARTIAL | Plain textarea implemented; native inspection pending |
| AC-WIN-P03-042 | UI reflects lifecycle states | PARTIAL | Typed toolbar/status wiring; native inspection pending |
| AC-WIN-P03-043 | New/Open/Save actions keyboard accessible | PARTIAL | Semantic buttons and textarea; native inspection pending |
| AC-WIN-P03-044 | File-dialog capability is least privilege | PASS | Capability/security validator |
| AC-WIN-P03-045 | No unrestricted frontend filesystem access | PASS | Shell boundary and security validator |
| AC-WIN-P03-046 | CSP/security baseline preserved | PASS | Security validator |
| AC-WIN-P03-047 | No Phase 4 Source Editor | PASS | Scope validator and source inspection |
| AC-WIN-P03-048 | No Phase 5 Preview/Mermaid implementation | PASS | Scope validator and source inspection |
| AC-WIN-P03-049 | No Phase 8 persistence | PASS | No database/settings dependency or path |
| AC-WIN-P03-050 | Rust fmt passes | PASS | Final `cargo fmt --all -- --check` |
| AC-WIN-P03-051 | Rust check passes | PASS | Final `cargo check --workspace` |
| AC-WIN-P03-052 | Strict Clippy passes | PASS | Final `cargo clippy ... -D warnings` |
| AC-WIN-P03-053 | Workspace tests pass | PASS | Final `cargo test --workspace`: 26 executable tests, 0 failures |
| AC-WIN-P03-054 | Filesystem integration tests pass | PASS | Platform unit + T1–T20 matrix |
| AC-WIN-P03-055 | WASM/Leptos release build passes | PARTIAL | Direct release WASM compilation passes; Trunk asset pipeline is blocked at nested metadata |
| AC-WIN-P03-056 | Native Tauri release build passes | PARTIAL | Direct shell release compilation passes; `cargo tauri build` is blocked at nested metadata |
| AC-WIN-P03-057 | Native Windows lifecycle validation passes | PENDING | Manual native run pending |
| AC-WIN-P03-058 | Native watcher evidence recorded | PENDING | Manual/native evidence pending |
| AC-WIN-P03-059 | Native stale-overwrite conflict evidence recorded | PENDING | Manual/native evidence pending |
| AC-WIN-P03-060 | Persian native lifecycle evidence recorded | PENDING | Manual/native evidence pending |
| AC-WIN-P03-061 | CI updated/validated | PARTIAL | Workflow and local contract updated; hosted run not executed |
| AC-WIN-P03-062 | macOS source preserved | PASS | Windows-scoped diff; no `MarkView/` change |
| AC-WIN-P03-063 | Phase 3 docs created | PASS | This directory |
| AC-WIN-P03-064 | OKF updated | PASS | New lifecycle architecture/components and updated indexes |
| AC-WIN-P03-065 | OKF/log.md updated | PASS | 2026-08-21 entry |
| AC-WIN-P03-066 | HANDOFF updated | PASS | Truthful Phase 3 checkpoint |
| AC-WIN-P03-067 | Final Git state recorded | PASS | `git status`, HEAD, and `git diff --check` |
| AC-WIN-P03-068 | Phase 4 readiness determined | PENDING | Depends on final Phase 3 status |

Phase 3 cannot be reported `COMPLETE` while release/native evidence or any
data-loss safety criterion remains open. The matrix is updated as those checks
are actually executed.
