# Windows Phase 0 Decision Register

This register is the short index of the twelve detailed ADRs. “Accepted” means
the Phase 0 product/architecture contract is adopted for planning; it does not
mean the implementation has been compiled or security-reviewed in a native
Windows build.

| ID | Decision | Status | ADR |
| --- | --- | --- | --- |
| D-WIN-P00-001 | Use Rust as the Windows domain/runtime language and keep the core platform-neutral | Proposed | [ADR-WIN-001](adrs/ADR-WIN-001-rust-domain-core.md) |
| D-WIN-P00-002 | Use Tauri 2 as the thin Windows desktop shell | Proposed | [ADR-WIN-002](adrs/ADR-WIN-002-tauri-shell.md) |
| D-WIN-P00-003 | Keep Windows work in the same repository with an explicit boundary | Accepted | [ADR-WIN-003](adrs/ADR-WIN-003-same-repository.md) |
| D-WIN-P00-004 | Treat plain Markdown source as the document authority and define two editor fidelity tiers | Accepted | [ADR-WIN-004](adrs/ADR-WIN-004-markdown-source-authority.md) |
| D-WIN-P00-005 | Use bundled offline Markdown/Mermaid rendering behind a hardened WebView2 boundary | Proposed | [ADR-WIN-005](adrs/ADR-WIN-005-renderer-webview2.md) |
| D-WIN-P00-006 | Use Windows Credential Manager through a fail-closed secret adapter | Proposed | [ADR-WIN-006](adrs/ADR-WIN-006-windows-secrets.md) |
| D-WIN-P00-007 | Use a typed, transactional document safety and persistence model | Proposed | [ADR-WIN-007](adrs/ADR-WIN-007-document-safety.md) |
| D-WIN-P00-008 | Keep AI providers behind a typed registry and proposal protocol | Proposed | [ADR-WIN-008](adrs/ADR-WIN-008-ai-provider-boundary.md) |
| D-WIN-P00-009 | Build the visual editor as a semantic Leptos surface with explicit source-fidelity guarantees | Proposed | [ADR-WIN-009](adrs/ADR-WIN-009-visual-editor.md) |
| D-WIN-P00-010 | Use a layered test pyramid plus native Tauri WebDriver E2E | Proposed | [ADR-WIN-010](adrs/ADR-WIN-010-testing-and-e2e.md) |
| D-WIN-P00-011 | Target Windows 11 x64 first and prove ARM64 before a GA claim | Accepted | [ADR-WIN-011](adrs/ADR-WIN-011-support-matrix.md) |
| D-WIN-P00-012 | Defer installer, signing, updater, and distribution details until a native spike proves the shell | Proposed | [ADR-WIN-012](adrs/ADR-WIN-012-release-evidence.md) |

Open questions and gate conditions are tracked in
[`RISK_REGISTER.md`](RISK_REGISTER.md) and
[`ACCEPTANCE_MATRIX.md`](ACCEPTANCE_MATRIX.md).
