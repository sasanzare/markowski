# Windows Phase 1 evidence

This log records commands and observations made against the production
`windows/` workspace. The ignored disposable Phase 0 smoke was not used for
these results.

## Git baseline

| Check | Result |
| --- | --- |
| Repository | `D:\All projects\markowski` |
| Branch | `main` |
| Starting/current HEAD | `9883985718f1edc50984be548f9561c28dd0e827` |
| HEAD subject | `docs(windows): complete Phase 0 remediation evidence` |
| Initial status | Clean; no staged or unstaged changes |
| macOS paths | No `MarkView/`, `MarkViewTests/`, or `MarkView.xcodeproj/` changes |
| Phase 0 artifacts | Existing ignored `.artifacts/windows-phase0/` preserved |

Commands executed:

```text
git status --short
git status
git branch --show-current
git rev-parse HEAD
git log -1 --oneline
```

## Toolchain

```text
rustc -Vv
rustc 1.97.1 (8bab26f4f 2026-07-14)
host: x86_64-pc-windows-msvc

rustup component list --installed --toolchain 1.97.1-x86_64-pc-windows-msvc
rustfmt and clippy present

trunk --version
trunk 0.21.14

cargo-tauri --version
cargo-tauri 2.11.4
```

`wasm32-unknown-unknown` and `x86_64-pc-windows-msvc` are declared in and
installed for `windows/rust-toolchain.toml`.

## Rust gates

All commands ran from `D:\All projects\markowski\windows` with
`CARGO_HOME=D:\All projects\.cargo-markowski` and the production workspace
target directory.

| Command | Exit | Result |
| --- | ---: | --- |
| `cargo fmt --check` | 0 | PASS |
| `cargo check --workspace` | 0 | PASS |
| `cargo clippy --workspace --all-targets --all-features -- -D warnings` | 0 | PASS |
| `cargo test --workspace` | 0 | PASS; 3 core tests + 3 shell tests, 0 failed |

The compiler emitted a future-incompatibility advisory for transitive
`proc-macro-error2`; it did not affect the exit status or introduce a Phase 1
warning in the workspace.

## Frontend and native builds

Frontend command from `windows/apps/desktop-ui`:

```text
trunk build --release
```

Exit `0`. The production `dist/` contained:

```text
index.html                                  1,136 bytes
styles-43f40e5a0bd56c4d.css                  1,055 bytes
markowski-desktop-ui-cfe1b0d58cb2fa28.js    29,801 bytes
markowski-desktop-ui-cfe1b0d58cb2fa28_bg.wasm 138,192 bytes
```

Tauri command from `windows/apps/desktop-shell`:

```text
cargo-tauri build --no-bundle --ci
```

Exit `0`. Tauri ran the configured `cd desktop-ui && trunk build --release`
hook from `windows/apps`, then produced:

```text
D:\All projects\markowski\windows\target\release\markowski-desktop-shell.exe
size: 9,988,096 bytes
SHA-256: A37136AF1440E2E8D67784C3AE74A665DC51CFF31603263624696FBEBB8663B1
```

The WASM SHA-256 was:

```text
97C8CA63C50CA0AE204C2B87CFC2DC13AB0172AFA959DF9B54B7B1254C96571D
```

## Security and CI validation

```text
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
Phase 1 security validation: PASS

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1
Phase 1 CI contract validation: PASS
```

The security script verified the exact five capability permissions, no wildcard
or remote runtime CSP directive, required local/WASM/IPC/object restrictions,
and no credential-shaped literals in production Rust/TOML/JSON source.

The workflow is present at
`.github/workflows/windows-phase1.yml`. A GitHub-hosted run was not dispatched
in this session; only its local contract validation was run.

The dependency audit path is documented in `windows/SECURITY_CHECKS.md` but
`cargo-audit` was not installed or run. No live provider, API key, signing
certificate, or telemetry service was used.

## Native launch and WebView2 evidence

The exact production executable above was launched on the current Windows host
using the Windows Computer Use runtime. The returned window was uniquely:

```text
process:D:\All projects\markowski\windows\target\release\markowski-desktop-shell.exe
title: Markowski
```

The WebView2 accessibility/document text was:

```text
Markowski
Windows Development Build
Native bridge connected
Version
0.1.0
Platform
windows
```

The screenshot-backed window state visibly rendered the Markowski UI, the
development-build label, the status card, version `0.1.0`, and platform
`windows`. The UI received the typed `get_app_info` response from Rust rather
than a browser fallback. The native close control was clicked and a fresh app
enumeration returned no remaining `markowski-desktop-shell` process/window.

## Final Git state

The final validation commands were run from the repository root:

```text
git diff --check                         exit 0
git status --short --untracked-files=all
git status --short -- MarkView MarkViewTests MarkView.xcodeproj
git diff
```

The final status contained only the Phase 1 `HANDOFF.md`/OKF updates and the
new `.github/workflows/windows-phase1.yml`, `docs/windows/phase-01/`, and
`windows/` files. The macOS-scoped status was empty. No staged changes, commit,
push, branch change, reset, or history rewrite was made.

## Not run

- GitHub Actions hosted execution: workflow created and statically validated,
  but no remote run was dispatched from this session.
- `cargo audit`: documented but not installed/run.
- macOS `xcodebuild` or Swift tests: unavailable on this Windows host; no
  macOS pass is claimed.
- Installer, signing, updater, file associations, and all Phase 2+ features:
  explicitly out of scope.
