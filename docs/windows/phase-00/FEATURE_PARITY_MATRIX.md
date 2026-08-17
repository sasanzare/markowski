# Windows Feature Parity Matrix

This matrix is the Phase 0 parity contract. “Observed” means supported by the
macOS source or tests; it does not mean the macOS test suite ran in this Windows
environment. Windows status is intentionally explicit so later phases cannot
silently convert a proposal into a promise.

Status values used here: `VERIFIED`, `PARTIAL`, `UNVERIFIED`, `DEFERRED`, and
`N/A`. Phase ownership is the planned implementation phase from the master
plan, not work completed in Phase 0.

| ID | Capability | macOS observed behavior / evidence | Existing tests or fixtures | Windows v1 contract | Owner phase | Status |
| --- | --- | --- | --- | --- | --- | --- |
| PAR-DOC-001 | Open `.md`/`.markdown` | `DocumentModel.swift:4-19`; UTF-8 file document | `DocumentModelTests`, `basic.md` | Open and save UTF-8 Markdown from file picker and shell association | P1 | VERIFIED |
| PAR-DOC-002 | Open `.mmd` | Mermaid UTType and readable type in `DocumentModel.swift:9-19` | Mermaid fixtures | Open as a text document and render as a diagram | P1/P3 | VERIFIED |
| PAR-DOC-003 | Create document | `DocumentActions.swift`; new file defaults to Downloads and atomic empty write | `DocumentModelTests` | Create untitled document without requiring network/account | P1 | VERIFIED |
| PAR-DOC-004 | Metadata | `DocumentLoader.swift:27-76` computes path, size, dates, lines, words, characters | `DocumentModelTests` | Expose metadata without leaking sensitive content to logs | P1 | VERIFIED |
| PAR-DOC-005 | Autosave ownership | SwiftUI `DocumentGroup` owns open-document autosave; binding mutation is used | `DocumentModelTests` | A single Rust document coordinator owns save state; no competing direct write | P1 | VERIFIED |
| PAR-DOC-006 | External file change | `FileWatcher.swift:22-65`, `DocumentView.swift:561-580` debounces and preserves unsaved memory | `DocumentModelTests`, `MarkViewTests` | Detect write/rename/delete/permission/identity changes and present recoverable conflict | P1 | PARTIAL |
| PAR-DOC-007 | Content hash | SHA-256 of UTF-8 text in `DocumentSafetyService.swift:4-9` | `AIOperationTests`, `MarkViewTests` | Hash canonical source snapshot and file identity; fail closed on read error | P1/P5 | VERIFIED |
| PAR-DOC-008 | Encoding policy | UTF-8 read, ASCII fallback in `DocumentModel.swift:27-40`; loader is UTF-8 only | `DocumentModelTests` | Explicit UTF-8/BOM/invalid-byte and line-ending policy; no silent data loss | P1 | PARTIAL |
| PAR-REN-001 | Preview mode | Bundled WebKit renderer in `RendererWebView.swift:155-177` | `MarkViewTests`, fixture corpus | Local WebView2 preview with deterministic block/source metadata | P3 | VERIFIED |
| PAR-REN-002 | GFM Markdown | Bundled marked configured in `renderer.html:418-428` | `MarkViewTests`, `full-markdown.md`, `showcase.md` | Match supported GFM semantics or document intentional differences | P3 | VERIFIED |
| PAR-REN-003 | Mermaid | Bundled Mermaid, SVG render in `renderer.html:430-456` | `flowchart.mmd`, `sequence.mmd`, `invalid.mmd` | Offline Mermaid rendering; invalid syntax is visible and non-destructive | P3 | VERIFIED |
| PAR-REN-004 | Code blocks | Renderer syntax-highlights fences; assistant uses language-aware styling | `MarkViewTests`, `full-markdown.md` | Preserve fence content exactly; no executable code interpretation | P3 | VERIFIED |
| PAR-REN-005 | Tables / HTML tables | Markdown and HTML tables modelled/serialized; complex spans use HTML | `RichTextCanvasTests`, `full-markdown.md` | Render and edit supported table subset; preserve raw unsupported HTML | P3/P4 | PARTIAL |
| PAR-REN-006 | Local images | `mvlocal` serves supported files; current resolver permits standardized absolute paths | image cases in `MarkViewTests` | Document-root allowlist, traversal/symlink checks, supported MIME only | P3 | PARTIAL |
| PAR-REN-007 | Theme and zoom | Renderer has light/dark CSS, SwiftUI zoom state | `MarkViewTests` | DPI-aware light/dark/zoom without re-render selection loss | P3 | VERIFIED |
| PAR-REN-008 | Rendered selection/ranges | `data-mv-start` and length callbacks in `renderer.html:1049+` | `MarkViewTests` | Typed WebView bridge maps rendered selections to source ranges safely | P3/P4 | PARTIAL |
| PAR-EDT-001 | Source mode | Editable plain `NSTextView` with syntax highlighting and undo | `MarkViewTests`, `RichTextCanvasTests` | Plain source editor remains authoritative and supports native undo | P2/P4 | VERIFIED |
| PAR-EDT-002 | Semantic Editor mode | TextKit 2 canvas uses `RichDocument`; no visible Markdown syntax | `RichTextCanvasTests` | Leptos editor with semantic blocks and a documented fidelity tier | P4 | VERIFIED |
| PAR-EDT-003 | Headings/styles | Rich model and formatter support headings and inline styles | `RichTextCanvasTests`, `MarkViewTests` | Structural editing with source round-trip golden tests | P4 | VERIFIED |
| PAR-EDT-004 | Lists/tasks/quotes | Rich model supports list styles, tasks, nested content, quotes | `RichTextCanvasTests`, `descending-list.md` | Preserve marker/task semantics and indentation | P4 | VERIFIED |
| PAR-EDT-005 | Links/images | Inline links and local image attachments are parsed/read back | `RichTextCanvasTests` | Safe link activation; image paths never become arbitrary native reads | P4 | VERIFIED |
| PAR-EDT-006 | Tables as objects | `RichTextDocumentBridge.swift:74-132` uses live table attachments | `RichTextCanvasTests` | Cell editing, row/column/alignment operations, keyboard traversal | P4 | VERIFIED |
| PAR-EDT-007 | Raw/unknown block preservation | `BlockContent.raw` retains unsupported HTML/frontmatter | parser/serializer tests | Preserve bytes or visibly mark normalization; never silently discard | P4 | PARTIAL |
| PAR-EDT-008 | Source fidelity | Serializer normalizes model output; Preview block edits splice exact ranges | `RichTextCanvasTests`, `MarkViewTests` | Separate byte-preserving source and semantic-editor guarantees | P4/P6 | PARTIAL |
| PAR-EDT-009 | Undo/revert | `DocumentView.swift:1093-1112`; AI proposal undo/revert exists | `AIOperationTests`, `MarkViewTests` | Every applied local/AI edit has undo; persisted snapshot/revert policy | P1/P6 | VERIFIED |
| PAR-NAV-001 | Block index | `DocumentIndex.swift` creates block IDs, headings, line ranges, quotes | `MarkViewTests` | Stable logical references independent of DOM IDs | P2 | VERIFIED |
| PAR-NAV-002 | Find/search | Literal case-insensitive source/preview search in `DocumentNavigator.swift` | `MarkViewTests` | Same query semantics in Source, Editor, Preview | P2 | VERIFIED |
| PAR-NAV-003 | Source↔Preview navigation | WebView bridge and source line scroll in `DocumentNavigator.swift:13-65,220-254` | `MarkViewTests` | Map source line/range to visible target without script injection | P2/P3 | VERIFIED |
| PAR-NAV-004 | AI reference navigation | Index and renderer use candidate text/heading/quote lookup | `AIOperationTests`, `MarkViewTests` | References resolve to current snapshot or are marked stale | P2/P6 | VERIFIED |
| PAR-AI-001 | Provider protocol | `AIProvider.swift:3-6` defines model, stream, connection operations | `MarkViewTests` | Rust trait with typed request/stream/error contracts | P5 | VERIFIED |
| PAR-AI-002 | Provider registry | Gemini, OpenAI, Anthropic, Mock, and compatible providers in `AIService.swift:134-207` | `MarkViewTests` | Registry remains replaceable; no provider logic in UI | P5 | VERIFIED |
| PAR-AI-003 | Dynamic model discovery | `AIService.swift:278-300`; provider endpoints fetch models | `MarkViewTests` | Refresh, cache, provider/model capability metadata | P5 | VERIFIED |
| PAR-AI-004 | Model enablement/preferences | `AIModels.swift:114-221` uses local preferences and configured state | `MarkViewTests` | Local settings only; no remote account dependency | P5 | VERIFIED |
| PAR-AI-005 | Streaming/cancellation | `AIService.swift:404-478` guards generations and preserves partial stream | `MarkViewTests` | Cancellation aborts network and never applies partial output | P5 | VERIFIED |
| PAR-AI-006 | Usage/reasoning controls | `AITokenUsage.swift`, service records provider/estimated usage and reasoning effort | `MarkViewTests` | Local counters, limits, daily/manual reset, no secret/content logs | P5 | VERIFIED |
| PAR-AI-007 | Chat persistence | `ChatStorage.swift`; local Application Support index/session/blob files | `ChatStorageTests` | App-data sessions and attachment blobs, atomic writes, GC, migration | P5 | VERIFIED |
| PAR-AI-008 | Document context | Current document is sent on explicit send through AI service | `MarkViewTests` | No upload before explicit Send; visible privacy state | P5 | VERIFIED |
| PAR-AI-009 | Selection/pinned context | Preview/source/reply selections become explicit prompt context | `MarkViewTests` | Exact selected text and source location are user-visible | P5 | VERIFIED |
| PAR-AI-010 | Attachments | `PromptAttachments.swift`; images/pasted text normalized and size-limited | `MarkViewTests`, `DocumentTextExtractorTests` | Provider capability filter, limits, local storage, explicit send only | P5 | VERIFIED |
| PAR-AI-011 | Structured operations | `DocumentOperation.swift`, `AIOperationTests`; all-or-nothing typed operations | `AIOperationTests` | Validate schema, handles, bounds, and base snapshot before proposal | P6 | VERIFIED |
| PAR-AI-012 | Diff/review | `DiffEngine.swift`; proposal summary and line diff | `AIOperationTests`, `MarkViewTests` | Deterministic diff for review; large files have bounded algorithm | P6 | VERIFIED |
| PAR-AI-013 | Apply/discard | Sidebar review, apply, discard, conflict alert, force path | `AIOperationTests`, `MarkViewTests` | Apply requires current-memory + disk base match; discard is reversible state only | P6 | PARTIAL |
| PAR-AI-014 | Undo/revert applied AI edit | Proposal records original document and service exposes applied/reverted status | `AIOperationTests`, `MarkViewTests` | Undo and snapshot revert survive restart policy or are explicitly scoped | P6 | VERIFIED |
| PAR-AI-015 | Stale proposal handling | On-disk hash check at `AIAssistantSidebar.swift:1734-1741`; memory race remains | `AIOperationTests` | Stale if memory, file bytes, or file identity changed; no Apply Anyway without fresh diff | P6 | PARTIAL |
| PAR-SEC-001 | Secret storage | Keychain service exists, but fallback is Base64 `UserDefaults` (`KeychainService.swift:34-64`) | `MarkViewTests` | Windows Credential Manager only; fail closed and redact diagnostics | P5 | PARTIAL |
| PAR-SEC-002 | Local-first storage | Documents/files/chats/attachments are local; AI optional | `ChatStorageTests`, `DocumentModelTests` | No telemetry or cloud sync required for core editing | P1/P5 | VERIFIED |
| PAR-SEC-003 | Network scope | Providers use HTTPS APIs after user request; links may open externally | provider tests/source audit | Allow only configured HTTPS provider endpoints and explicit external links | P5 | PARTIAL |
| PAR-SEC-004 | Renderer isolation | Local WebView and bridge exist; CSP not observed, Mermaid loose | renderer source audit | Bundle-only CSP, typed commands/events, origin/navigation checks | P3 | PARTIAL |
| PAR-UX-001 | Persian/RTL | `PersianTextTools`, direction-aware canvas, IRANSansX assistant styling | `RichTextCanvasTests`, `MarkViewTests` | Persian UI/content and direction behavior in all three modes | P4/P7 | VERIFIED |
| PAR-UX-002 | Mixed bidi/IME | Per-paragraph direction and native text controls observed; Windows IME unverified | RTL tests | Persian/Latin, code, URL, IME composition and cursor tests on Windows | P4/P7 | UNVERIFIED |
| PAR-UX-003 | Accessibility/motion | SwiftUI accessibility labels and Reduce Motion paths are present in views | `MarkViewTests` | Keyboard navigation, focus, contrast, screen reader labels, reduced motion | P7 | UNVERIFIED |

The full acceptance gate for this matrix is in
[`ACCEPTANCE_MATRIX.md`](ACCEPTANCE_MATRIX.md). A `PARTIAL`, `UNVERIFIED`, or
`DEFERRED` row is not a license to ship; it is a named future verification.
