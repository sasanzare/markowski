# Windows Phase 3 Evidence

## Baseline

- Repository: `D:\All projects\markowski`
- Branch: `main`
- Starting and current baseline before this work: `e208cb91ad3e6961e3c6f382927fdb38d470882f`
- Baseline commit: `docs(windows): complete Phase 2 DPI validation`
- Pre-change working tree: clean.
- macOS source trees were not edited by this Phase 3 change.

## Automated checks executed so far

The following commands were run from `windows/` on the Windows host:

| Command | Result |
| --- | --- |
| `cargo fmt --all -- --check` (baseline and final) | PASS |
| `cargo check --workspace` (baseline) | PASS; existing future-incompatibility advisory only |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` (baseline) | PASS; existing future-incompatibility advisory only |
| `cargo test --workspace` (baseline) | PASS; 10 tests, 0 failures |
| `cargo fmt --all` after implementation | PASS |
| `cargo check --workspace` (final) | PASS; existing future-incompatibility advisory only |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` (final) | PASS; existing future-incompatibility advisory only |
| `cargo test --workspace` (final) | PASS; 26 executable tests, 0 failures; doc-tests had no tests |
| `cargo test -p markowski-platform-windows` | PASS; 4 unit tests, 1 T1–T20 integration test, 0 failures |
| `cargo build --target wasm32-unknown-unknown --release -p markowski-desktop-ui` (including post-Reload UI change) | PASS |
| `cargo build --release -p markowski-desktop-shell` | PASS; direct release shell compilation |
| `windows/scripts/validate-security.ps1` | PASS |
| `windows/scripts/validate-phase2.ps1` | PASS |
| `windows/scripts/validate-phase3.ps1` | PASS |
| `windows/scripts/validate-ci.ps1` | PASS |
| `git diff --check` | PASS; only Git line-ending normalization warnings |

One intermediate strict-Clippy run failed on two test-only unused parameters
and two UI lint findings; those were corrected before the final Clippy pass.
One intermediate integration compile failed because a test used a non-ASCII
Rust byte-string literal; the test was corrected to compare UTF-8 string bytes,
then the integration test passed. These are implementation corrections, not
waived failures.

## Filesystem and data-loss evidence

`crates/markowski-platform-windows/tests/document_lifecycle.rs` exercises the
required T1–T20 matrix in an isolated temporary directory. It covers:

- `.md` and `.mmd` open, existing save, first Save As, atomic replacement, and
  failed-destination preservation;
- external change, clean reload, dirty conflict, delete, and rename handling;
- Persian and emoji filenames, Persian content, empty files, CRLF/LF, UTF-8
  BOM preservation, and a deterministic 1 MiB document;
- typed invalid-target/permission failure handling; and
- a revision-bound save proposal where a newer edit remains dirty.

The platform unit tests also run a real `notify` watcher against temporary
files. The own-save regression saves through `DocumentCoordinator`, waits for
the underlying watcher event when delivered, reconciles it, and asserts that
the result is not `Conflict` and that disk/persisted hashes agree.

The lifecycle toolbar exposes New, Open, Save, Save As, and explicit Reload;
Reload is disabled for untitled/missing/renamed targets and asks for explicit
discard confirmation before replacing dirty memory.

## Native evidence status

Direct Rust release compilation is complete, but the Tauri release build hook
and manual lifecycle evidence are not. `trunk build --release` and
`cargo tauri build --no-bundle --ci` both stop before compilation because their
nested `cargo metadata` process receives Windows `Access is denied`; direct
`cargo metadata --no-deps --format-version 1` passes. An escalated retry was
rejected by the environment usage limit, so no workaround or native pass is
claimed. The required next native checks are:

1. build the release WASM frontend and unbundled Tauri executable;
2. launch the executable and exercise New/Open/Save/Save As/Reload;
3. modify, delete, and rename a file externally while observing typed states;
4. exercise Persian/Unicode paths, empty and long-path behavior, and a stale
   overwrite attempt; and
5. capture concise results under ignored `.artifacts/windows-phase3/`.

No native pass is claimed here until the executable and the visible behavior
have been inspected on this host.

## CI and security status

The workflow `.github/workflows/windows-phase1.yml` now runs the Phase 2
regression validator and Phase 3 scope validator in addition to the existing
Rust, WASM, native, security, and least-privilege checks. Hosted GitHub Actions
has not been triggered from this local task. All four local validators pass.
