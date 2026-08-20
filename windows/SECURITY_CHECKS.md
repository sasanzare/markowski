# Windows security checks

Phase 1 and Phase 2 keep the security surface small and local. The production
shell has no shell, filesystem, process, HTTP, updater, credential-manager,
telemetry, or remote-runtime permission. The only exposed application command
is the typed `get_app_info` command; Phase 2 adds no native command.

## Automated checks

Run the repository-owned capability, CSP, and source scan with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1
```

The security script checks the committed Tauri capability allowlist, rejects
wildcard or remote runtime CSP directives, and looks for credential-shaped
literals in production source/configuration. The Phase 2 validator additionally
checks local fonts/assets, explicit LTR roots, the unchanged permission set,
minimum window size, and the absence of Phase 3 document-lifecycle symbols.

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

License review and secret scanning remain release-CI gates. The Phase 2 UI
fixtures are local-only and do not log their Persian or document-like text.
