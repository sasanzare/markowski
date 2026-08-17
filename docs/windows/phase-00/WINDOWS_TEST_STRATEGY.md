# Windows Test and E2E Strategy

Status: PROPOSED — the test architecture is frozen for implementation, but no
Windows application has been built in Phase 0.

## Test pyramid

### Pure Rust unit tests

Run without Windows, WebView2, network, or a real filesystem where possible:

- Markdown parser/serializer and fixed-point round trips;
- source-range/block mapping and Mermaid fence metadata;
- Persian/RTL transforms and mixed-direction metadata;
- operation schema validation, handle resolution, and all-or-nothing batches;
- diff output and large-input fallback;
- AI stream state machine, cancellation, truncation, and generation guards;
- token usage and model capability filtering;
- log redaction and secret-free error serialization.

### Rust integration tests

Use temporary directories and fakes:

- atomic save, crash/interruption simulation, backup/recovery;
- UTF-8/BOM/invalid-byte/line-ending policy;
- file identity/revision/hash conflicts;
- watcher self-write suppression and external write/rename/delete/permission
  transitions;
- chat/session/attachment persistence, schema migration, and garbage
  collection;
- provider HTTP fakes for model discovery, streaming, error payloads, timeout,
  cancellation, and attachment capability behavior;
- Credential Manager adapter with a test seam that proves no fallback write.

### Renderer and browser tests

Run the bundled frontend in a deterministic browser fixture where no native
binary is needed:

- preview corpus comparison for Markdown, tables, code, links, images, Mermaid,
  invalid Mermaid, dark mode, zoom, and block ranges;
- CSP/resource audit, including an assertion that no remote script or unexpected
  connection is used;
- hostile raw HTML and image-path corpus;
- typed renderer message schema and origin/bridge rejection;
- keyboard navigation, selection, source-range mapping, and reduced motion.

### Native Windows E2E

Use the official Tauri WebDriver route after the app exists. The current Tauri
documentation describes WebdriverIO with `@wdio/tauri-service`; it can use the
embedded provider or native `tauri-driver` on Windows/Linux. The Windows suite
must exercise a real packaged or release-like binary with WebView2, not only a
Vite/browser preview.

Required scenarios:

1. launch without network and open a fixture;
2. switch Preview/Editor/Source and preserve source;
3. edit, undo, save, close, reopen, and verify bytes/hash;
4. external write/rename/delete/permission conflict and safe recovery;
5. Markdown/Mermaid render and invalid diagram behavior;
6. Persian/RTL/IME and keyboard traversal;
7. search/navigation across all modes;
8. provider model discovery with a fake HTTPS endpoint or test provider;
9. stream, cancel, malformed response, proposal review, stale conflict,
   apply/discard, undo/revert;
10. attachment limits and explicit-send assertions;
11. secret-store failure and log redaction;
12. installer/update behavior at each supported WebView2 mode.

## Test fixtures

Start with the existing `TestDocuments/` corpus and add Windows-specific golden
cases for:

- CRLF and LF;
- UTF-8 BOM and non-ASCII Persian text;
- long paths and spaces/non-Latin directory names;
- read-only files, inaccessible directories, renamed files, and reparse points;
- large documents near diff/render thresholds;
- image references with traversal, absolute path, and symlink/reparse cases;
- Mermaid diagrams containing labels, links, HTML-like text, and invalid syntax;
- mixed Markdown/HTML/raw frontmatter and table spans.

Every golden document must have a stable fixture identifier, expected source
hash, expected render/range metadata, and an explanation when semantic Editor
serialization intentionally differs from source bytes.

## CI lanes

| Lane | Trigger | Required checks |
| --- | --- | --- |
| PR | Every pull request | Rust fmt/check/test, frontend type/build, parser/serializer goldens, security/redaction/path tests, docs/link validation |
| Main | Merge to main | PR checks plus Windows x64 build, WebView2 smoke, native E2E, artifact manifest, dependency audit |
| Release candidate | Version/tag candidate | Main checks plus clean-machine install, offline render, upgrade/rollback, signing verification, support matrix, performance budgets |
| macOS regression | Windows change touching shared docs/assets/contracts | Existing Xcode build/tests and selected UI/golden checks on a macOS runner |
| ARM64 pre-GA | Before Windows ARM64 claim | Native ARM64 build and smoke/E2E on real or supported virtual hardware |

## Failure classification

Each run reports `PASS`, `FAIL`, `BLOCKED`, or `NOT RUN` with environment and
artifact evidence. Missing Xcode on Windows is `NOT RUN`, not a passing macOS
regression. A browser-only renderer check is not a native Tauri/WebView2 pass.

## Performance and reliability budgets

Budgets are to be measured in Phase 1 spikes, not invented here. The initial
measurement set is: first render time by document size; edit-to-preview latency;
save/reopen latency; search latency; memory during large-document rendering;
stream cancellation latency; diff latency and memory; startup with/without
WebView2 cache. Regressions must include fixture size, machine, build, and
whether a debugger was attached.

## Release evidence

The release artifact must include the exact Rust/frontend lockfiles, WebView2
mode/version policy, installer target, signing identity reference (not a
secret), test run IDs, support matrix, SBOM/dependency audit, and rollback
instructions. No Phase 0 release artifact is produced.
