# Markowski Windows Phase 1 implementation

**Phase:** 1 — Rust/Tauri Foundation & CI  
**Status:** COMPLETE  
**Implementation root:** [`windows/`](../../../windows/)

## Scope

Phase 1 establishes the smallest production Windows foundation without
implementing product features. The workspace contains one platform-neutral
core crate, one Leptos/WASM frontend, and one thin Tauri 2 shell. Document
lifecycle, Markdown parsing, rendering, editing, navigation, persistence,
credentials, AI, and packaging remain out of scope.

## Workspace

```text
windows/
├── Cargo.toml
├── Cargo.lock
├── rust-toolchain.toml
├── README.md
├── SECURITY_CHECKS.md
├── apps/
│   ├── desktop-ui/
│   └── desktop-shell/
├── crates/
│   └── markowski-core/
├── scripts/
│   ├── validate-ci.ps1
│   └── validate-security.ps1
└── tests/e2e/README.md
```

`target/`, frontend `dist/`, and Tauri-generated schema output are build
artifacts. They are ignored; the application `Cargo.lock` is retained in the
working tree for reproducible dependency resolution.

## Architecture implemented

- `markowski-core` contains application identity/version types, the typed
  `get_app_info` request/response contract, and safe IPC error DTOs. It has no
  Tauri, WebView2, Windows API, HTTP, or filesystem implementation dependency.
- `desktop-ui` is a minimal CSR Leptos application. It invokes only the typed
  `get_app_info` command and renders loading, success, and safe error states.
- `desktop-shell` owns startup, immutable app state, the typed command adapter,
  Tauri window configuration, local structured logging, and safe startup/runtime
  error boundaries. The command handler contains no domain feature logic.
- The capability file exposes only the Tauri core permissions required by the
  shell plus the command-specific `allow-get-app-info` permission. No shell,
  filesystem, process, HTTP, updater, or credential permission is present.
- CSP is local-only and includes the narrowly required WASM and Tauri IPC
  directives. No CDN or remote script is used.
- A small production icon is generated from `icons/markowski.svg` because the
  Windows resource compiler requires `icon.ico`. macOS assets and the Phase 0
  smoke source were not copied.

## Toolchain and dependency decision

`rust-toolchain.toml` pins stable Rust `1.97.1` MSVC with `rustfmt`, `clippy`,
`x86_64-pc-windows-msvc`, and `wasm32-unknown-unknown`. The exact current-stable
pin is justified by the verified host's broken stable alias installation,
which reported clippy installed while omitting `cargo-clippy.exe`. The
workspace package MSRV remains `1.87`; the small manifest pins retain the
known Rust 1.87-compatible dependency set recorded by Phase 0.

Resolved application versions include Tauri `2.11.5`, Tauri CLI `2.11.4`,
Leptos `0.7.8`, and Trunk `0.21.14`. These versions were resolved by Cargo and
the local toolchain; no dependency version was copied into production from
the disposable smoke without a successful production build.

## Validation summary

The exact command and runtime evidence is recorded in
[`EVIDENCE.md`](EVIDENCE.md). The local Phase 1 gates passed:

- `cargo fmt --check`
- `cargo check --workspace`
- `cargo clippy --workspace --all-targets --all-features -- -D warnings`
- `cargo test --workspace` — 6 unit tests passed; no failures
- release Leptos/WASM build with Trunk
- release Tauri native executable build with `--no-bundle --ci`
- security/CSP/capability/source scan
- workflow contract validation
- native launch, WebView2 render, typed IPC response, and clean close

The GitHub-hosted workflow was not dispatched from this local session. Its
required Windows jobs and commands are present and its repository-owned static
contract validator passes. `cargo audit` is documented as the next dependency
security command but was not installed or run in this phase.

## Explicitly not implemented

No Phase 2 or later product behavior was added: there is no workspace layout,
theme system, RTL implementation, document open/save, autosave, watcher,
source editor, preview, Mermaid, search, persistence, Credential Manager, AI,
attachments, agentic edit, diff, installer, updater, or file association.
