# Markowski Windows Phase 3 — Document Lifecycle & Filesystem Safety

## Status

`PARTIAL` while native release-build, launch, and manual lifecycle evidence are
still being collected. The platform-neutral domain model, Windows filesystem
adapter, typed shell commands, minimal lifecycle surface, automated filesystem
matrix, and local validation contracts are implemented.

Phase 3 is intentionally limited to document lifecycle and filesystem safety.
It does not implement the Phase 4 Source Editor, Phase 5 Markdown/Mermaid
preview, or Phase 8 durable persistence.

## Scope and source layout

The implementation is split into three layers:

1. `windows/crates/markowski-document/` contains path validation, UTF-8/BOM
   decoding, newline normalization, content and disk hashes, the document
   state machine, save proposals, and the filesystem-independent coordinator.
2. `windows/crates/markowski-platform-windows/` owns stable reads, same-directory
   flushed temporary writes, Windows replacement, native file dialogs, and the
   debounced `notify` watcher.
3. `windows/apps/desktop-shell/` exposes only typed lifecycle commands and
   serializes access through `AppState`; `windows/apps/desktop-ui/` provides a
   deliberately plain textarea surface and lifecycle controls.

The Windows shell does not receive a generic filesystem capability. The native
adapter returns validated document paths to the typed shell, and the browser
surface never reads or writes files directly.

## Supported documents and text policy

- Supported extensions are `.md` and `.mmd`, case-insensitive.
- File bytes must be valid UTF-8, optionally beginning with a UTF-8 BOM.
- The BOM is detected and preserved on save.
- In-memory text uses LF separators.
- A loaded CRLF document is written with CRLF after an edit. LF documents stay
  LF. Mixed input is deterministically normalized to LF after an edit.
- Empty files are valid. Binary or non-UTF-8 content is rejected with a typed
  `UnsupportedEncoding` result.
- Paths must be absolute and have a supported extension. Unicode path names are
  passed through `PathBuf` and wide Win32 dialog APIs.

## State machine

The state machine is implemented by `DocumentSession` and surfaced through
`DocumentState`:

| State | Meaning | Safe actions |
| --- | --- | --- |
| `Untitled` | No persisted target exists. | Edit, Save As, explicit New/Open after confirmation. |
| `Saved` | Memory and the last accepted disk revision match. | Edit, Save, Save As, Reload. |
| `Dirty` | Memory differs from the accepted persisted memory revision. | Save, Save As, continue editing. |
| `Saving` | A save proposal is being written. | UI remains responsive; concurrent save requests are coordinated. |
| `ExternalChanged` | Clean memory no longer matches the current disk snapshot. | Reload, Save As, continue without silent overwrite. |
| `Conflict` | Dirty memory and a changed disk revision coexist. | Reload, Save As, or keep editing; ordinary Save is refused. |
| `Missing` | The persisted target was deleted or disappeared. | Save As or recover in memory; no automatic recreation. |
| `ExternallyRenamed` | A watcher reported a rename/move that cannot be safely followed. | Save As or explicit resolution. |
| `SaveError` | A non-conflict write/read failure occurred. | Retry or use Save As, with memory retained. |

External watcher events are reconciled against an actual read and SHA-256
comparison. Raw event type alone never causes an automatic reload or overwrite.

## Save and concurrency model

Each save captures the target, encoded bytes, memory generation, logical memory
hash, and expected disk snapshot in a `SaveAttempt`. Completion updates the
persisted revision only when that attempt is accepted. If editing happens while
the write is in progress, the newer generation remains dirty after completion.

For an existing path, the Windows adapter compares the current disk bytes with
the expected snapshot before creating a temporary file and again immediately
before replacement. A mismatch returns `DiskConflict`; it never silently
overwrites the external revision. The shell's `Mutex<DocumentCoordinator>`
serializes command access, and the UI autosave refuses known conflict/missing/
rename states and uses a debounce rather than synchronous per-keystroke saves.

## Atomic write contract

1. Read and fingerprint the existing target.
2. Validate the expected revision or explicit Save As overwrite confirmation.
3. Create a collision-resistant temporary file in the target's parent.
4. Write all bytes and call `sync_all` before replacement.
5. Replace with `MoveFileExW(REPLACE_EXISTING | WRITE_THROUGH)` on Windows.
6. Read the final target and verify its SHA-256 against the attempted bytes.

The original target is never truncated before the replacement operation. A
failed deterministic temp write removes its temporary file. If replacement is
ambiguous, the complete temporary copy is retained for conservative recovery;
the user receives only a typed `AtomicReplaceFailed` message and no raw path or
OS error is logged.

## Watcher and external changes

`WindowsWatcherHandle` watches the target's parent directory with `notify` and
coalesces events for 250 ms. Each callback asks the coordinator to inspect the
actual target. During `Saving`, reconciliation is ignored; after a successful
save the final disk snapshot is authoritative, so the underlying replace event
does not create a false conflict. A clean external edit becomes
`ExternalChanged`; a dirty external edit becomes `Conflict`; deletion keeps
the in-memory text and becomes `Missing`; rename/move is surfaced as
`ExternallyRenamed` when the event identifies a rename.

## Typed IPC and UI boundary

The shell exposes `new_document`, `open_document`, `update_document_content`,
`save_document`, `save_document_as`, `reload_document`, and
`get_document_state`, all with typed request/response/error values. New/Open
carry an explicit `discard_changes` confirmation flag, so a direct caller
cannot silently replace dirty memory. Save As uses the native overwrite prompt.

The UI polls typed state at a bounded interval and also receives a native state
event. It requests content only when the memory generation changes. New/Open/
close protection uses an explicit confirmation, and native close handling asks
whether to Save, Discard, or Cancel when the document is dirty. Untitled
autosave is intentionally absent; it requires an explicit Save As.

## Scope boundaries and limitations

- The Phase 3 editing surface is a replaceable plain textarea. It is not a
  Source Editor and has no syntax model, preview, Mermaid renderer, or AI edit
  path.
- Recent documents are session-only at most; no durable settings/database was
  introduced.
- Long-path behavior is represented by wide path handling and a large dialog
  buffer, but native dialog behavior for every Windows long-path policy still
  requires manual evidence on the target host.
- A watcher failure is visible as typed status/error information; save safety
  remains enforced by the pre-write disk comparison.

## Validation references

- [Acceptance matrix](ACCEPTANCE_MATRIX.md)
- [Evidence record](EVIDENCE.md)
- [Windows domain crate](../../../windows/crates/markowski-document/src/lib.rs)
- [Windows filesystem adapter](../../../windows/crates/markowski-platform-windows/src/lib.rs)
- [Tauri shell](../../../windows/apps/desktop-shell/src/lib.rs)
- [Leptos lifecycle surface](../../../windows/apps/desktop-ui/src/app.rs)
