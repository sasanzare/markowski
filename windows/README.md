# Markowski Windows development workspace

This directory is the production Rust/Tauri/Leptos boundary for the Windows
edition. Phase 2 provides the bilingual desktop shell, local UI state, themes,
resizable workspace, and AI sidebar placeholder. Phase 3 adds filesystem-backed
`.md`/`.mmd` document lifecycle, revision-safe atomic saves, external-change
reconciliation, typed dialogs/IPC, and a deliberately plain lifecycle text
surface. Source editing, rendering, Mermaid preview, AI, and durable
persistence remain later phases.

## Toolchain

The workspace uses the stable MSVC Rust toolchain and declares the
`x86_64-pc-windows-msvc` and `wasm32-unknown-unknown` targets in
`rust-toolchain.toml`. Rust `1.97.1` is the current stable release used for
Phase 1 validation. It is pinned because the host's stable alias installation
was missing its clippy executable; the exact version is not a product
requirement and can be relaxed after that toolchain installation is repaired.

The manifests carry a small set of transitive compatibility pins because the
verified Rust 1.87 host otherwise resolves current Leptos/Tauri dependency
versions that require Rust 1.88. The pins are documented and can be revisited
when the verified minimum toolchain advances.

Install the development tools once when they are not already available:

```powershell
cargo install trunk --locked
cargo install tauri-cli --locked
```

The native build also requires the Windows MSVC Build Tools, Windows SDK, and
Microsoft Edge WebView2 Runtime. No API keys, signing certificates, or live
provider credentials are required for this workspace.

## Commands

Run these commands from `windows/`:

```powershell
cargo fmt --check
cargo check --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace

powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase3.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1
```

Build the frontend directly from `windows/apps/desktop-ui/`:

```powershell
trunk build --release
```

Run the development desktop app from `windows/apps/desktop-shell/`:

```powershell
cargo tauri dev
```

Build the native Windows executable without creating an installer:

```powershell
cargo tauri build --no-bundle --ci
```

Run the static security and capability checks from `windows/`:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase3.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1
```

The dependency-audit path is documented in `SECURITY_CHECKS.md`. The native
WebDriver route is reserved as a future automation boundary in
`tests/e2e/README.md`; Phase 2 and Phase 3 native evidence is recorded manually
through the actual WebView2 release window and documented under
`docs/windows/phase-02/` and `docs/windows/phase-03/`.
