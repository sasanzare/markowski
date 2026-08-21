# Windows security checks

Phase 1 through Phase 3 keep the security surface small and local. The
production shell has no shell, generic frontend filesystem, process, HTTP,
updater, credential-manager, telemetry, or remote-runtime permission. Phase 3
adds only typed document lifecycle commands; filesystem authority remains in
the native Windows adapter and native file dialogs.

## Automated checks

Run the repository-owned capability, CSP, and source scan with:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-security.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase2.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-phase3.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File scripts/validate-ci.ps1
```

The security script checks the committed Tauri capability allowlist, rejects
wildcard or remote runtime CSP directives, looks for credential-shaped
literals in production source/configuration, and checks that document dialogs
remain behind the typed shell boundary. The Phase 2 validator is retained as a
regression check for local fonts/assets, explicit LTR roots, the unchanged
permission set, and minimum window size. The Phase 3 validator checks the
document/platform crates, typed lifecycle commands, atomic-write/watcher
fragments, and the absence of Phase 4/8 dependencies.

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
