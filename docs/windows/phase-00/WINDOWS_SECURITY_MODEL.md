# Windows Security Model

Status: PROPOSED — security controls are design requirements until exercised by
the native Windows implementation and threat tests.

## Security objectives

- Keep local Markdown files and AI context under explicit user control.
- Treat Markdown, Mermaid, HTML, images, provider responses, attachments, and
  WebView messages as untrusted input.
- Keep API keys out of source, ordinary app storage, logs, crash reports, and
  renderer memory where possible.
- Prevent a compromised or navigated frontend from gaining arbitrary filesystem,
  process, credential, or network access.
- Ensure no AI response can modify a document without schema validation, base
  snapshot validation, visible diff review, and an explicit user action.
- Fail closed when a file, credential, origin, or revision cannot be verified.

## Threat model

| Asset | Threat | Required control | Verification |
| --- | --- | --- | --- |
| Markdown source | Local concurrent writer, malicious file, crash during save | Revision/hash/file-identity checks; temp + flush + atomic replace; recoverable conflict | Rust storage tests; Windows file-watch E2E |
| Unsaved edits | AI proposal or watcher overwrites current memory | Memory revision and source hash are part of proposal base; apply is transactional | `stale_proposal_*` tests; manual conflict scenario |
| API keys | Keychain failure, logs, crash dumps, UI bridge | Windows Credential Manager only; no reversible fallback; redacted DTOs/logs | Platform adapter tests; secret scan; negative storage test |
| Document content | Prompt logging, telemetry, provider error payload | Explicit Send only; no mandatory telemetry; structured redaction | Log fixture tests; network mock assertions |
| Renderer | XSS/HTML script, Mermaid unsafe behavior, crafted local image URL | Bundle-only CSP, sanitized raw HTML policy, Mermaid hardening, no remote scripts | CSP build check; hostile Markdown corpus; WebView2 E2E |
| Local files | `..`, absolute paths, reparse points, image probing | Canonicalize and enforce approved roots; reject symlink/reparse escapes | Path traversal and symlink tests |
| Tauri bridge | Forged command/event, broad capability, arbitrary IPC | Narrow typed commands, capability allowlist, origin/window validation, revision tokens | IPC schema tests; capability review |
| Provider response | Malformed JSON, huge stream, prompt injection, incorrect operation | Size/time limits, streaming state machine, typed operation validation, no direct mutation | Fake provider fuzz/negative tests |
| Attachments | Oversized or polyglot content, hidden uploads | Type/dimension/byte limits; provider capability filter; send-time explicitness | Attachment fixtures and upload assertions |
| WebView2 host | Navigation to hostile origin, script access to host | Navigation policy, origin checks, no generic proxies, least privilege | Native navigation tests |
| Logs | Bearer tokens, cookies, prompts, full document text | Redaction before formatting; bounded structured fields | Redaction golden tests |

## Tauri and WebView2 boundary

The Tauri capability set must be explicit and minimal. The main window receives
only the document, dialog, event, opener, and narrowly scoped platform
permissions it actually needs. A capability for remote URLs is not part of the
default editor surface. Newly registered commands are explicitly listed and
tested rather than relying on a broad default.

The frontend cannot be trusted merely because it is bundled. Every command must
validate its arguments in Rust. Every renderer message must validate its
structure, document session, revision, and origin/window label. No command may
accept a raw JavaScript expression, arbitrary native path, or provider-supplied
function.

WebView2 settings are least-privilege by default: no host objects, no arbitrary
navigation, no generic proxy, no unnecessary dialogs, and no elevation. The
host must check origin before consuming messages and before sending sensitive
data. The WebView2 user-data folder is app-owned and must use ordinary user
integrity; the app must not require administrator privileges for editing.

## Content Security Policy and local assets

The production renderer must declare a restrictive CSP in Tauri configuration.
It should allow only the bundled app origin, the IPC origin required by the
chosen Tauri setup, the renderer’s local image protocol, and the WASM execution
directive required by the actual Leptos build. It must not allow remote scripts,
wildcard connections, or an unbounded `data:`/`blob:` policy without a tested
reason.

The macOS baseline does not show a CSP in `renderer.html`; this is a Windows
hardening requirement, not a claim that the current renderer has one. The
renderer asset review must also decide whether raw HTML is disabled, sanitized,
or rendered in a deliberately isolated surface. Mermaid must not inherit the
observed `securityLevel: 'loose'` without a security review.

## File and image safety

The document resource resolver must:

1. parse a URL as data, not as a path command;
2. allow only supported image MIME/extensions;
3. resolve relative paths under approved document roots;
4. reject absolute paths unless the user explicitly imports/copies the asset;
5. canonicalize before containment checks;
6. reject traversal, reparse-point/symlink escapes, device paths, and alternate
   data streams where applicable;
7. never expose arbitrary file existence or error detail to the renderer;
8. return a typed “unavailable image” result without reading outside the scope.

## Secret lifecycle

The `SecretStore` trait has `put`, `get`, `delete`, and `status` operations. The
Windows adapter calls Credential Manager with an application-scoped target name
and treats any write/read failure as unavailable. The UI receives a boolean
status and remediation text, not a secret or raw Win32 error that could contain
identifiers. Migration from a future macOS/legacy store must be explicit and
one-way; no automatic Base64 import is permitted.

Secrets are excluded from:

- `tracing` fields and error chains;
- provider request/response bodies in debug logs;
- crash metadata and analytics;
- serialized chat messages unless a future product decision explicitly supports
  a user-visible “remember key” record in the secure store.

## AI proposal security protocol

```text
user submits request
  -> capture immutable document snapshot + revision + hash + file identity
  -> send only the explicitly permitted context/attachments
  -> receive bounded typed stream
  -> parse and validate schema/operations against the captured snapshot
  -> create proposal with base metadata and deterministic diff
  -> user reviews diff and change list
  -> re-read current memory and disk identity/hash
  -> apply transaction or show stale conflict
  -> publish new revision and undo record
```

Provider instructions and document content are not trusted policies. The
operation validator must reject unknown operations, unknown block handles,
invalid ranges, missing fields, oversized payloads, and partial batches. A
provider cannot request a native command or bypass the review state.

## Logging and redaction

Logs may contain event names, durations, sizes, provider/model identifiers,
status codes, and stable internal request IDs. They must not contain API keys,
authorization headers, cookies, full prompts, document text, attachment bytes,
raw provider payloads, or arbitrary filesystem contents. Redaction occurs before
serialization so a sink cannot recover the original field from an error chain.

## Security acceptance gates

The security model is not accepted for release until the test strategy proves:

- CSP and capability configuration are present and deny unlisted access;
- a hostile Markdown/Mermaid/image corpus cannot execute or read arbitrary local
  files;
- forged/remote/navigated WebView messages are ignored;
- secret store failures do not create ordinary-storage fallback records;
- stale AI proposals cannot overwrite current memory or disk;
- logs pass a negative secret/content scan;
- installers and updaters are signed and verified according to the release plan.
