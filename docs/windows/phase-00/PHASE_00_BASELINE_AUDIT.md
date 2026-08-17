# Markowski Windows Phase 0 Baseline Audit

Status: PARTIAL — the repository and macOS baseline are audited at source and
test level. The remediation host/toolchain is now verified and a disposable
Tauri/Leptos smoke is partially wired, but the user paused before dependency
completion, build, or native launch. This document is an audit record, not a
Phase 1 implementation.

## Scope and exit rule

This audit executes Phase 0 of
[`MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`](../MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md):

- establish the actual Git and repository baseline;
- describe the current macOS product from code, tests, fixtures, and OKF;
- turn the observed behavior into a traceable Windows parity contract;
- freeze a proposed Rust/Tauri 2/Leptos/WebView2 architecture and its ADRs;
- record security, persistence, rendering, editor, support, testing, and release
  decisions without creating the production Windows workspace.

No Swift source, Xcode project file, macOS asset, provider, or production
Windows runtime was changed for this phase. The only non-document housekeeping
change is the `.artifacts/` ignore rule.

## Repository and Git baseline

| Item | Observed value |
| --- | --- |
| Repository | `D:\\All projects\\markowski` |
| Branch | `main` |
| HEAD / starting commit | `7d85b84c55f64636c69e746c37e98781182459c5` |
| HEAD subject | `Stack download actions on iPhone layouts` |
| Remote | `origin` points to `git@github.com:sasanzare/markowski.git` |
| Initial status | `main...origin/main`; one pre-existing untracked `docs/windows/` directory containing the master plan |
| Staged changes at start | None |
| macOS source changes at start | None observed |

The existing untracked master plan is preserved. Phase 0 adds documents below
the same `docs/windows/` directory; remediation adds only ignored disposable
files under `.artifacts/`. No commit, branch change, reset, cleanup, or push is
part of this task.

## Repository documentation baseline

The repository’s project-specific instruction file is `AGENTS.md`. It identifies
`OKF/` as the established OKF v0.2 bundle and requires updates to the relevant
concept and `OKF/log.md` when architecture or behavior knowledge changes. The
root handoff is now maintained in [`HANDOFF.md`](../../../HANDOFF.md).

The existing knowledge bundle describes MarkView/Markowski as a native macOS
SwiftUI app. Its relevant architecture concepts are:

- `OKF/architecture/document-lifecycle.md`;
- `OKF/architecture/document-architecture.md`;
- `OKF/architecture/rendering-pipeline.md`;
- `OKF/architecture/navigation-search.md`;
- `OKF/architecture/ai-assistant.md`;
- `OKF/architecture/editing.md`.

The Windows extension is documented in this Phase 0 bundle and linked from a
new `OKF/architecture/windows-architecture.md` concept. The official OKF
version remains v0.2; there is no parallel knowledge framework.

## Source inventory

The application source is under `MarkView/` and the test target is
`MarkViewTests/`.

### Product and document lifecycle

| Area | Source evidence | Observed responsibility |
| --- | --- | --- |
| App entry | `MarkView/App/MarkViewApp.swift` | SwiftUI `Window`, `DocumentGroup(newDocument:)`, and Settings scene |
| File types and document wrapper | `MarkView/Models/DocumentModel.swift:4-45` | Markdown/plain text/Mermaid UTTypes; UTF-8 read with ASCII fallback; UTF-8 write |
| File loading and metadata | `MarkView/Services/DocumentLoader.swift:16-76` | Security-scoped URL access, UTF-8 loading, file metadata, line/word/character counts |
| Safe hash/write utility | `MarkView/Services/Safety/DocumentSafetyService.swift:4-34` | SHA-256 of UTF-8 text, external disk hash check, atomic write for files not owned by `DocumentGroup` |
| External watcher | `MarkView/Services/FileWatcher.swift:4-77` | macOS `DispatchSourceFileSystemObject`, write/rename/etc. events, 250 ms debounce |
| Document view | `MarkView/Views/DocumentView.swift:14-1111` | Preview/Editor/Source mode selection, autosave binding, watcher reconciliation, undo, navigation, AI integration |
| New/open actions | `MarkView/Services/Document/DocumentActions.swift` | New file in Downloads, open through `NSDocumentController`, recent document filtering |

The SwiftUI `DocumentGroup` owns the open document’s autosave lifecycle. The
application intentionally mutates the document binding rather than writing the
open file directly (`DocumentView.swift:1093-1105`). A Windows implementation
must preserve that ownership contract or replace it with an explicit, tested
document coordinator before claiming parity.

### Rendering and Markdown

| Area | Source evidence | Observed behavior |
| --- | --- | --- |
| Local WebView host | `MarkView/Views/RendererWebView.swift:22-177` | Bundled `renderer.html` loaded locally; `mvlocal` image scheme; WebKit message bridge |
| Markdown renderer | `MarkView/Resources/renderer.html:418-1050` | Local `marked`, block wrappers with source ranges, GFM/breaks, code, links, images, tables |
| Mermaid renderer | `MarkView/Resources/renderer.html:430-456` | Bundled Mermaid, client-side SVG rendering, `securityLevel: 'loose'` observed |
| Source-range bridge | `MarkView/Resources/renderer.html:486-564,1049-1050` | `data-mv-start`/length metadata and source-to-rendered navigation/edit callbacks |
| Markdown model | `MarkView/Models/Document/RichDocumentModel.swift:307-453` | Blocks, inline runs/styles, lists/tasks, tables, raw unsupported blocks, normalization |
| Parser | `MarkView/Services/Document/MarkdownDocumentParser.swift:3-84,519-677` | Headings, fences, tables, lists, quotes, HTML, paragraphs, inline formatting and links |
| Serializer | `MarkView/Services/Document/MarkdownDocumentSerializer.swift:3-215` | Markdown output; HTML table fallback for spans/per-cell/vertical alignment; normalized newline |

The renderer is local but the source baseline does not show a CSP in
`renderer.html`, permits raw HTML through the marked configuration, and sets
Mermaid security level to `loose`. These are baseline findings for Windows
hardening, not claims that the macOS renderer is safe against hostile documents.

### Visual editor and source fidelity

The Editor mode is a TextKit 2 `NSTextView` (`MarkView/Views/Editing/Canvas/RichTextCanvas.swift:4-42`)
fed by `RichDocument` and read back by
`MarkView/Views/Editing/Canvas/RichTextDocumentBridge.swift:4-9,662-694`.
Tables are live attachments (`RichTextDocumentBridge.swift:74-132`), generated
chrome is protected, and paragraph direction is inferred per paragraph.

This is semantic-model fidelity, not byte-preserving source editing. The model
keeps raw unsupported blocks, but an Editor edit can normalize whitespace,
formatting, list markers, table representation, and final newlines through the
parser/serializer. Preview block editing is different: it splices a selected
source range and is intended to leave unrelated bytes unchanged. Windows must
make this distinction visible in its editor contract and test both paths.

### Navigation and search

`MarkView/Services/Navigation/DocumentNavigator.swift:13-65,180-267` bridges
preview JavaScript, source line scrolling, and literal case-insensitive text
search. The index model is `MarkView/Models/DocumentIndex.swift`; it groups
blocks, headings, line ranges, and quotes and supplies stable handles for
references. Mermaid citations use a fallback query because source tokens can
disappear when the diagram becomes SVG.

### AI and provider registry

`MarkView/Services/AI/AIProvider.swift:3-6` defines model discovery, streaming,
connection testing, and the request contract. `AIProviderType` and
`AIModelCatalog` are in `MarkView/Models/AIModels.swift:3-221`.
`AIService.swift` routes Gemini, OpenAI, Anthropic, Mock, and OpenAI-compatible
providers for OpenRouter, Mistral, Groq, xAI, and DeepSeek. The service:

- refreshes models from providers (`AIService.swift:278-300`);
- computes a source hash before a request (`AIService.swift:379`);
- streams with cancellation and generation guards (`AIService.swift:404-478`);
- records provider or estimated token usage and reasoning effort;
- validates `document_operations` transactionally before creating a proposal
  (`AIService.swift:534-618`);
- retains original document, updated document, summary, changes, and hash in
  `AIEditProposal` (`AIModels.swift:236-279`).

The assistant sends current document/selection context only after the explicit
send action. Images and pasted text are normalized and provider-filtered in
`MarkView/Models/PromptAttachments.swift` and the AI sidebar. Chats and
attachment blobs persist locally through `MarkView/Services/AI/ChatStorage.swift`.

### AI safety and known baseline gaps

The intended flow is request → streamed response → schema/operation validation →
proposal → diff review → apply/discard → undo/revert. The source-level audit
found two important gaps to carry into the Windows contract:

1. `AIAssistantSidebar.swift:1734-1741` checks the on-disk hash before applying a
   proposal. It does not independently prove that the current in-memory
   document still equals the proposal base. An unsaved edit can therefore race
   an apply path while the disk remains unchanged. Windows must compare the
   current document snapshot and disk identity, fail closed, and require an
   explicit rebase/review path.
2. `MarkView/Services/Security/KeychainService.swift:34-64` falls back to
   Base64-encoded API keys in `UserDefaults` when Keychain calls fail. Base64 is
   not encryption and violates the Windows master-plan invariant that secrets
   never use plaintext or reversible storage as a fallback. Phase 0 documents
   this variance; it does not modify macOS source.

`DocumentSafetyService.hasFileChangedExternally` also returns `false` when the
file cannot be read (`DocumentSafetyService.swift:11-19`). Windows will treat
missing, unreadable, renamed, and identity-changed files as conflicts rather
than as “unchanged”.

### Persian, RTL, and mixed-direction behavior

`MarkView/Services/Editing/PersianTextTools.swift` and
`MarkView/Services/Editing/MarkdownFormatter.swift` provide Persian letter,
digit, punctuation, ZWNJ, whitespace, direction-marker, list, heading, link,
image, code, and table transforms. The rich-text bridge chooses paragraph
direction per text content. `renderer.css` and the assistant view use bundled
IRANSansX assets for Persian UI/replies. Windows must test mixed Persian/Latin
text, code spans, URLs, list markers, selection offsets, IME composition, and
bidirectional navigation rather than relying on visual inspection alone.

## Tests and fixture baseline

The test target contains 262 declared `test...` methods across six files, based
on the source-level count performed in Phase 0:

| Test file | Test methods | Focus |
| --- | ---: | --- |
| `AIOperationTests.swift` | 13 | operation decoding, handles, transactional behavior |
| `ChatStorageTests.swift` | 23 | local session/attachment persistence and cleanup |
| `DocumentModelTests.swift` | 36 | document model and lifecycle behavior |
| `DocumentTextExtractorTests.swift` | 16 | text/PDF/Office extraction limits and formats |
| `MarkViewTests.swift` | 80 | broad document, navigation, formatting, AI, and rendering-adjacent behavior |
| `RichTextCanvasTests.swift` | 94 | parser/serializer/editor projection, tables, styles, RTL |

The test corpus includes eight Markdown/Mermaid fixtures under `TestDocuments/`:
`basic.md`, `descending-list.md`, `flowchart.mmd`, `full-markdown.md`,
`invalid.mmd`, `markowski-commercial-demo.md`, `sequence.mmd`, and `showcase.md`.
The fixture SHA-256 values and sizes are recorded in `EVIDENCE.md`.

The macOS test target could not run here because this is Windows and
`xcodebuild`/Swift are unavailable. The counts are inventory evidence, not test
execution evidence.

## Assets and dependency baseline

The renderer bundles `renderer.html`, `renderer.css`, `marked.min.js`, and
`mermaid.min.js` under `MarkView/Resources/`. A Windows reuse decision must
re-audit licenses, versions, CSP compatibility, Mermaid configuration, and
resource loading before copying assets. No new JavaScript or Rust dependency
was installed in Phase 0.

## Baseline contradictions and required Windows corrections

| Finding | Impact | Windows requirement |
| --- | --- | --- |
| Keychain reversible fallback | Secret exposure if secure storage fails | Credential Manager only; fail closed; migration/error state; no UserDefaults secret fallback |
| Disk-only proposal hash check | Possible overwrite of unsaved memory | Compare base hash with current memory and disk; stale proposals cannot apply silently |
| Read-error treated as unchanged | Delete/permission/rename can bypass safety | Fail closed with typed conflict state |
| Renderer has no observed CSP; Mermaid `loose` | Untrusted Markdown/diagram surface can reach scripts/HTML | Bundle-only assets, strict CSP, sanitized/isolated HTML, Mermaid hardening, typed bridge |
| Absolute image paths accepted by `mvlocal` | Potential local image file disclosure | Resolve only approved document-local roots; reject traversal, symlinks, and arbitrary absolute paths |
| WYSIWYG serializer normalizes Markdown | Byte-level source fidelity is not automatic | Use explicit fidelity tiers and golden tests; preserve unknown/raw blocks and exact source when required |
| Windows machine identity inconsistent | Support claim could be wrong | Verify supported Windows SKU/build in a clean matrix before release gate |

## Phase 0 remediation checkpoint

The Windows toolchain gate is no longer blocked by the host. Rust MSVC
`1.87.0`, Visual Studio Build Tools `18.9.0`, `cl.exe`, `link.exe`, Windows SDK
`10.0.26100.0`, WebView2 `151.0.4129.86`, and the WASM target were verified.
Microsoft’s release mapping resolves local build `26200.8875`/`25H2` as Windows
11 25H2 x64; the stale registry `ProductName` remains documented but is not a
release blocker. The official Leptos/Tauri scaffold and typed smoke bridge now
exist only under the ignored `.artifacts/windows-phase0/` directory.

The user paused work while `cargo install trunk --locked` was compiling. No
WASM build, Tauri build, native executable, WebView2 launch, or typed IPC runtime
evidence exists yet.

## Phase 0 conclusion

The macOS baseline is sufficiently described to define a parity contract, and
the proposed Windows boundaries and decisions are documented in this bundle.
Phase 0 remains `PARTIAL` because the native Windows build and launch gates are
not proven yet. Phase 1 is therefore `NOT_READY`.
