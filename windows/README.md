# Markowski Windows development workspace

This directory is the production Rust/Tauri/Leptos boundary for the Windows
edition. It is intentionally a small Phase 1 foundation. Document lifecycle,
rendering, editing, navigation, persistence, credentials, AI, and packaging
remain later phases.

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
```

The dependency-audit path is documented in `SECURITY_CHECKS.md`. The native
WebDriver route is reserved as a skeleton in `tests/e2e/README.md`; Phase 1
does not claim product E2E scenarios.
