# Windows Phase 1 security checks

Phase 1 keeps the security surface small and local. The production shell has
no shell, filesystem, process, HTTP, updater, or credential-manager
permission. The only exposed operation is the typed `get_app_info` command.

## Automated checks

Run the repository-owned capability, CSP, and source scan with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
```

The script checks the committed Tauri capability allowlist, rejects wildcard
or remote runtime CSP directives, and looks for credential-shaped literals in
the production source/configuration.

## Dependency audit path

When `cargo-audit` is available, run:

```powershell
cargo audit --locked
```

For a clean Windows runner, the dependency can be installed without a project
change using:

```powershell
cargo install cargo-audit --locked
```

License review and secret scanning remain release-CI gates. Phase 1 does not
add a large policy framework or connect to a remote telemetry service.
