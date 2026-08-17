# Markowski for Windows — Rust Master Plan

**Document:** `MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md`  
**Version:** 1.0  
**Status:** Execution Baseline  
**Target:** Markowski for Windows  
**Primary language:** Rust  
**Primary desktop framework:** Tauri 2  
**UI:** Leptos/WASM (Rust)  
**Windows web runtime:** Microsoft Edge WebView2  
**Canonical upstream/fork:** `https://github.com/sasanzare/markowski`  
**Planning date:** 2026-08-16

---

## 0. Purpose of this Master Plan

این سند نقشه اجرایی رسمی برای ساخت نسخه Windows برنامه **Markowski** با رویکرد **Rust-first** است.

هدف صرفاً ساخت یک Markdown Editor ساده نیست. نسخه Windows باید تا زمان Release Candidate، از نظر رفتار و قابلیت‌های اصلی با نسخه فعلی macOS به **Feature Parity قابل اثبات** برسد؛ در عین حال معماری آن نباید یک port مستقیم از Swift باشد، بلکه باید یک پیاده‌سازی تمیز، امن، تست‌پذیر و قابل توسعه در Rust باشد.

این Master Plan طوری طراحی شده که توسعه پروژه به صورت Phase-by-Phase با Codex و مدل **GPT-5.6 Luna Max** انجام شود.

قانون اصلی:

> هیچ Phase بعدی نباید فقط به این دلیل شروع شود که «کد نوشته شده است». هر Phase باید Acceptance Criteria، تست، Evidence، مستندات OKF و HANDOFF خود را ببندد.

---

# 1. Product Baseline

## 1.1 Markowski چیست؟

Markowski یک workspace برای Markdown است که در نسخه فعلی macOS:

- فایل‌های معمولی `.md` و `.mmd` را باز می‌کند.
- فرمت اختصاصی سند ایجاد نمی‌کند.
- Preview دارد.
- Editor بصری دارد.
- Source mode دارد.
- Autosave دارد.
- Mermaid را به صورت local render می‌کند.
- جستجو و navigation داخل سند دارد.
- از Persian/RTL و mixed RTL/LTR پشتیبانی می‌کند.
- AI Assistant در کنار سند دارد.
- AI می‌تواند به بخش‌های سند reference بدهد.
- AI می‌تواند تغییرات سند را پیشنهاد دهد.
- تغییر AI قبل از Apply قابل review است.
- Undo و Revert برای agentic edit وجود دارد.
- چند AI Provider را پشتیبانی می‌کند.
- API Key توسط storage امن سیستم‌عامل نگهداری می‌شود.
- attachmentهای مختلف را برای مدل‌های پشتیبانی‌شده می‌پذیرد.
- بدون account قابل استفاده است.
- سند تا قبل از ارسال صریح کاربر به AI upload نمی‌شود.

نسخه Windows باید این اصول را حفظ کند.

---

# 2. Non-Negotiable Product Invariants

موارد زیر invariant هستند و Codex حق تغییر آن‌ها را بدون ADR و تأیید صریح مالک محصول ندارد.

## 2.1 Plain Markdown Is the Source of Truth

Source of truth همیشه Markdown اصلی کاربر است.

ممنوع:

- proprietary document format
- database-only document storage
- silent conversion of `.md`
- destructive normalization
- rewriting unrelated parts of a file during a local edit

## 2.2 Local-First

خواندن، نوشتن، Preview، Mermaid، Search و Editing باید بدون اینترنت کار کنند.

Network فقط برای قابلیت‌هایی که واقعاً نیاز دارند مجاز است، از جمله:

- AI API request
- model catalog fetch
- connection test
- explicit updater checks

## 2.3 AI Is Optional

برنامه بدون API Key باید کاملاً برای Markdown editing قابل استفاده باشد.

نبود AI Provider نباید باعث:

- startup failure
- disabled editor
- disabled preview
- network error loop

شود.

## 2.4 User Controls Every AI Edit

هیچ AI response اجازه ندارد مستقیماً و بدون review سند را overwrite کند.

Agentic edit باید از این مسیر عبور کند:

`request -> response -> validation -> proposal -> diff review -> user apply/discard -> undo/revert`

## 2.5 Secret Isolation

API Key و secret:

- داخل Markdown نوشته نمی‌شوند.
- داخل log نوشته نمی‌شوند.
- داخل telemetry نوشته نمی‌شوند.
- داخل plain JSON/settings ذخیره نمی‌شوند.
- داخل Git قرار نمی‌گیرند.

## 2.6 Offline Renderer

`marked.js`, `mermaid.js` و هر asset لازم برای Preview باید bundle شود.

Preview نباید برای render کردن Markdown از CDN استفاده کند.

## 2.7 macOS Must Not Be Broken

نسخه Windows باید بدون شکستن نسخه موجود macOS وارد repository شود.

تغییر در Swift/macOS source فقط وقتی مجاز است که:

1. واقعاً لازم باشد.
2. دلیل در ADR نوشته شود.
3. macOS regression validation وجود داشته باشد.

---

# 3. Windows Product Scope

## 3.1 Target Platforms

Release v1 Windows:

- Windows 11 x64 — mandatory
- Windows 11 ARM64 — build + smoke validation before GA
- Windows 32-bit — out of scope
- Windows 10 — not a release requirement for v1

## 3.2 Windows UX Principle

نسخه Windows نباید clone ظاهری macOS باشد.

باید:

- identity و flow اصلی Markowski را حفظ کند.
- با Windows conventions سازگار باشد.
- keyboard-first باشد.
- scaling و DPI صحیح داشته باشد.
- dark/light theme صحیح داشته باشد.
- accessibility استاندارد داشته باشد.
- RTL/LTR را بدون خراب شدن layout مدیریت کند.

---

# 4. Architecture Decision

## 4.1 Chosen Stack

### Native/Application Layer

- Rust stable
- Tauri 2
- Tokio
- Serde

### UI Layer

- Leptos
- WASM
- HTML/CSS
- minimal `wasm-bindgen` / `web-sys` interoperability

### Rendering

- WebView2
- bundled `marked.js`
- bundled `mermaid.js`
- bundled renderer CSS/assets

### Networking

- `reqwest`
- async streaming
- provider-specific adapters

### Persistence

ترجیح معماری:

- lightweight structured preferences: local app config/store
- chat/history/structured operational data: SQLite when persistence complexity justifies it
- documents themselves: filesystem only

### Secrets

Windows Credential Manager using native Windows APIs through Rust/`windows` bindings.

No plaintext secret fallback.

### File Watching

Rust filesystem watcher with Windows-compatible backend.

### Hashing

SHA-256 for document revision safety.

### Logging

Structured local logs with mandatory secret redaction.

---

# 5. Why Tauri 2 + Leptos

## 5.1 Why Tauri

Tauri اجازه می‌دهد:

- application/backend logic در Rust باشد.
- executable سبک‌تر از Electron باقی بماند.
- Windows integration انجام شود.
- WebView2 برای rich UI و Markdown rendering استفاده شود.
- در آینده Linux و macOS نیز با بخش بزرگی از همین Rust core هدف قرار گیرند.
- capability/permission boundaries تعریف شود.

## 5.2 Why Leptos

Leptos اجازه می‌دهد بخش عمده UI نیز با Rust نوشته شود و:

- state management در Rust باقی بماند.
- frontend dependency surface کوچک‌تر شود.
- TypeScript business logic ایجاد نشود.
- core types در صورت نیاز بین Rust UI و native backend share شوند.

## 5.3 JavaScript Policy

هدف «Rust-first» است، نه «ممنوعیت مطلق JavaScript».

JavaScript فقط در موارد browser-native و محدود مجاز است، مثل:

- `marked.js`
- `mermaid.js`
- adapter بسیار کوچک برای editor/selection/render bridge
- کتابخانه editor فقط در صورتی که Phase Editor Spike اثبات کند راه‌حل Rust/WASM کیفیت کافی ندارد

JavaScript نباید محل business logic اصلی، AI orchestration، file safety یا secret handling باشد.

---

# 6. Repository Strategy

نسخه Windows باید در همان repository اصلی نگهداری شود.

ساختار پیشنهادی:

```text
markowski/
├─ MarkView/                     # existing macOS Swift source
├─ MarkViewTests/                # existing macOS tests
├─ OKF/                          # canonical project knowledge
├─ TestDocuments/                # shared golden/test documents
├─ windows/
│  ├─ Cargo.toml                 # Windows Rust workspace
│  ├─ rust-toolchain.toml
│  ├─ apps/
│  │  ├─ desktop-ui/             # Leptos/WASM UI
│  │  └─ desktop-shell/          # Tauri application
│  ├─ crates/
│  │  ├─ markowski-core/
│  │  ├─ markowski-document/
│  │  ├─ markowski-markdown/
│  │  ├─ markowski-navigation/
│  │  ├─ markowski-ai/
│  │  ├─ markowski-diff/
│  │  ├─ markowski-storage/
│  │  ├─ markowski-security/
│  │  ├─ markowski-platform-windows/
│  │  └─ markowski-test-support/
│  ├─ assets/
│  ├─ tests/
│  │  ├─ fixtures/
│  │  ├─ integration/
│  │  ├─ security/
│  │  └─ e2e/
│  └─ scripts/
├─ HANDOFF.md
└─ ...
```

این ساختار در Phase 0 قابل اصلاح است، اما separation زیر باید حفظ شود:

`UI != Tauri IPC != domain/core != platform-specific Windows`

---

# 7. Layering Rules

## 7.1 `markowski-core`

فقط domain types/state machineها.

نباید مستقیم به موارد زیر وابسته باشد:

- Tauri
- WebView
- Windows API
- filesystem implementation
- HTTP provider implementation

## 7.2 `markowski-document`

مسئول:

- document model
- encoding
- metadata
- revision/hash
- save safety
- external-change contracts
- document session state

## 7.3 `markowski-markdown`

مسئول:

- block model
- Markdown source ranges
- source editing operations
- formatting
- Mermaid detection/validation
- Persian text helpers
- source-to-render metadata

## 7.4 `markowski-navigation`

مسئول:

- `DocumentIndex`
- `DocumentBlock`
- `DocumentLocation`
- search state
- source/preview location resolution

## 7.5 `markowski-ai`

مسئول:

- AI provider traits
- provider implementations
- prompt construction
- response schema
- streaming
- token accounting
- model preferences
- attachment preparation
- request state machine

نباید UI dependency داشته باشد.

## 7.6 `markowski-diff`

مسئول:

- line/block diff
- proposal model
- safe apply
- revert snapshot

## 7.7 `markowski-security`

مسئول:

- secret abstraction
- redaction
- sensitive-data rules
- security policy helpers

## 7.8 `markowski-platform-windows`

تنها محل مناسب برای مستقیم استفاده کردن از Windows APIهایی مثل:

- Windows Credential Manager
- shell integration
- file associations
- native filesystem edge cases
- Windows-specific notifications/integration

## 7.9 Tauri Shell

Tauri commandها باید thin adapter باشند.

ممنوع:

- business logic حجیم داخل command handlers
- duplicated validation
- direct secret exposure to frontend
- arbitrary filesystem access

---

# 8. Shared Domain Contracts

تا حد ممکن contractهای Windows باید conceptually با macOS برابر باشند.

مدل‌های کلیدی:

```text
Document
DocumentMetadata
DocumentRevision
DocumentBlock
DocumentIndex
DocumentLocation
SearchMatch
PreviewSelection
AIProvider
AIModel
AIMessage
AIContentBlock
AIRequestState
AIUsage
AIModelPolicy
AIEditProposal
DocumentOperation
DiffChunk
Attachment
AppSettings
```

اسم دقیق Rust typeها در Phase معماری قابل تغییر است، اما semantics نباید بدون ADR تغییر کند.

---

# 9. Feature Parity Matrix

| Capability | Windows v1 Target | Phase |
|---|---|---:|
| Open `.md` | Required | 3 |
| Open `.mmd` | Required | 5 |
| New Markdown file | Required | 3 |
| Recent files | Required | 3 |
| Autosave | Required | 3 |
| Atomic safe save | Required | 3 |
| External change detection | Required | 3 |
| SHA-256 revision guard | Required | 3 |
| Preview | Required | 5 |
| Source mode | Required | 4 |
| Visual Editor | Required | 6 |
| Tables/lists/task lists | Required | 6 |
| Links/images | Required | 6 |
| Code blocks | Required | 5/6 |
| Mermaid | Required | 5 |
| Search | Required | 7 |
| TOC/navigation | Required | 7 |
| Source ↔ Preview navigation | Required | 7 |
| Selection actions | Required | 7/13 |
| Persian typography | Required | 2/6 |
| Mixed RTL/LTR | Required | 2/6 |
| Light/Dark | Required | 2 |
| AI Sidebar | Required | 12 |
| Gemini | Required | 10 |
| OpenAI | Required | 10 |
| Anthropic | Required | 10 |
| OpenRouter | Required | 10 |
| Mistral | Required | 10 |
| Groq | Required | 10 |
| xAI | Required | 10 |
| DeepSeek | Required | 10 |
| Mock provider | Required | 10 |
| Searchable model picker | Required | 11 |
| Model allow-list | Required | 11 |
| Token usage accounting | Required | 11 |
| Per-model token limit | Required | 11 |
| Manual/daily reset | Required | 11 |
| Reasoning effort | Required where provider supports | 11 |
| Streaming | Required | 10/12 |
| AI document reference | Required | 13 |
| Attachments | Required | 13 |
| Agentic document operations | Required | 14 |
| Diff review | Required | 14 |
| Apply / Discard | Required | 14 |
| Undo / Revert | Required | 14 |
| Credential Manager | Required | 9 |
| File association | Required | 15 |
| Installer | Required | 17 |
| Signed release path | Required for GA | 17 |
| Update path | Required before GA | 17 |

---

# 10. Global Quality Gates

هر Phase باید در حد scope خودش این gateها را رعایت کند.

## Rust

```bash
cargo fmt --check
cargo check --workspace
cargo clippy --workspace --all-targets --all-features -- -D warnings
cargo test --workspace
```

در صورت وجود WASM-specific crate:

- wasm build validation
- frontend unit/component tests
- compile validation for target

## Security

- dependency vulnerability scan
- license/policy scan
- secret scan
- no credentials in fixtures
- no sensitive request header logging

## Windows

برای Phaseهایی که UI/runtime را تغییر می‌دهند:

- native Windows build
- real launch
- no startup panic
- DPI sanity
- dark/light sanity
- keyboard sanity

## E2E

پس از آماده شدن shell:

- automated WebDriver-based tests
- native Windows runner
- exact evidence output

## Documentation

در هر Phase:

- OKF updated
- `OKF/log.md` updated
- `HANDOFF.md` updated
- Acceptance Matrix updated
- known limitations explicit

---

# 11. Development Governance for Codex

## 11.1 First Actions in Every Phase

Codex باید قبل از edit:

1. `git status`
2. current branch
3. exact HEAD
4. read root `AGENTS.md`
5. read this Master Plan
6. read `OKF/index.md`
7. read relevant OKF architecture/components/views/playbooks
8. inspect relevant source-of-truth code
9. inspect `HANDOFF.md`
10. inspect current tests
11. identify scope boundary
12. report baseline before implementation

## 11.2 Source of Truth Priority

در صورت conflict:

1. User's current explicit instruction
2. Phase prompt
3. This Master Plan
4. repository `AGENTS.md`
5. accepted ADRs / decision register
6. OKF
7. implementation comments
8. assumptions

اگر conflict مهم وجود داشت، Codex نباید silently یکی را انتخاب کند؛ آن را در Phase report ثبت کند.

## 11.3 Git Safety

مگر در Phase prompt صریحاً مجاز شده باشد:

- no push
- no force-push
- no rebase
- no reset --hard
- no amend
- no deleting unrelated user work

Commit نیز فقط در صورت مجاز بودن prompt انجام شود.

## 11.4 Mistake Log

اگر Codex:

- assumption اشتباه کرد
- test را اشتباه تفسیر کرد
- bug ناشی از تصمیم خودش ایجاد کرد
- pattern غلطی را تکرار کرد
- requirement را جا انداخت

باید یک یادداشت کوتاه و عملی در mistakes log ثبت کند.

Windows development environment preference:

`D:\All projects\Mistakes\mistakes.md`

اگر فایل یا مسیر وجود نداشت، بدون اجازه مسیر سیستم را تخریب یا جایگزین نکند؛ فقط در گزارش ثبت کند.

## 11.5 HANDOFF

`HANDOFF.md` باید حداقل شامل:

- current phase
- status
- exact branch/HEAD
- working tree state
- implemented items
- unimplemented items
- decisions/ADRs
- tests and results
- blockers
- security notes
- next safe action
- files that future agent must read first

باشد.

---

# 12. Status Model

هر Phase فقط یکی از این statusها را داشته باشد:

### `NOT_STARTED`

هیچ implementation معتبر وجود ندارد.

### `IN_PROGRESS`

کار در حال انجام است و هنوز acceptance gate کامل نشده.

### `PARTIAL`

بخش اصلی انجام شده ولی یک یا چند acceptance واقعی/evidence ناقص است.

### `BLOCKED`

عامل خارجی یا dependency اجازه تکمیل نمی‌دهد.

### `COMPLETE`

تمام acceptanceهای mandatory همراه evidence معتبر PASS شده‌اند.

Codex حق ندارد test غیرقابل اجرا را با عبارت‌هایی مثل "should pass" به `COMPLETE` تبدیل کند.

---

# 13. Phase 0 — Baseline Audit, Parity Contract & Architecture Freeze

## Goal

قبل از نوشتن Windows application code، repository، نسخه macOS و OKF به baseline قابل اتکا تبدیل شوند.

## Scope

- inventory کل repository
- inventory قابلیت‌های macOS
- inventory tests
- inventory assets
- بررسی README / RELEASE_NOTES / OKF
- بررسی source code برای رفتارهایی که OKF خلاصه کرده
- feature parity contract
- Windows architecture ADRs
- Rust/Tauri feasibility spike
- Visual Editor feasibility spike design
- repository placement decision
- CI strategy
- security model
- persistence model
- release target definition

## Required ADRs

حداقل:

- ADR-WIN-001: Tauri 2 + Rust architecture
- ADR-WIN-002: Leptos/WASM UI
- ADR-WIN-003: same repository strategy
- ADR-WIN-004: local-first document model
- ADR-WIN-005: renderer reuse strategy
- ADR-WIN-006: Windows Credential Manager
- ADR-WIN-007: AI provider architecture
- ADR-WIN-008: visual editor architecture
- ADR-WIN-009: persistence boundaries
- ADR-WIN-010: testing/evidence architecture
- ADR-WIN-011: Windows support matrix
- ADR-WIN-012: update/signing strategy

## Deliverables

- Windows baseline audit
- feature inventory
- parity matrix
- architecture diagrams
- risk register
- decision register
- acceptance matrix
- `HANDOFF.md`
- OKF Windows extension proposal
- no production feature implementation

## Exit Gate

Phase 0 = COMPLETE only when:

- macOS feature baseline is documented
- each Windows parity feature has owner phase
- all critical unknowns have ADR or explicit spike
- no contradiction remains between README/OKF/code for core scope
- Windows toolchain can compile a minimal Rust/Tauri app
- CI plan is executable
- HANDOFF exists

---

# 14. Phase 1 — Rust/Tauri Foundation & CI

## Goal

ایجاد foundation بدون business feature.

## Scope

- Rust workspace
- Tauri desktop shell
- Leptos UI shell
- toolchain pin
- formatter
- clippy
- tests
- dependency policy
- structured errors
- structured logging
- Tauri capabilities baseline
- Windows GitHub Actions
- WebDriver test skeleton
- build scripts

## Mandatory Architecture

- thin IPC
- typed commands/events
- no arbitrary shell access
- no broad filesystem permission
- no secrets
- no AI implementation

## CI Jobs

حداقل:

1. format
2. check
3. clippy
4. unit tests
5. Windows build
6. frontend/WASM build
7. dependency/security checks

## Exit Gate

- clean compile
- clippy `-D warnings`
- tests PASS
- native Windows app launches
- GitHub Actions Windows workflow executes successfully
- no feature creep

---

# 15. Phase 2 — Windows Shell, Layout, Theme, RTL/LTR Foundation

## Goal

ساخت UI shell واقعی Markowski.

## Scope

- welcome/start view
- main workspace
- document area
- AI sidebar placeholder
- mode switch container
- toolbar/menu architecture
- status/metadata areas
- resizable panes
- light/dark/system themes
- app typography
- IRANSansX integration if licensing/repository assets permit
- RTL/LTR direction model
- mixed direction rendering tests
- high DPI scaling
- keyboard focus order

## Required UX States

- no document
- document open
- AI sidebar open/closed
- source/editor/preview modes
- narrow window
- high scale factor

## Exit Gate

Visual shell is usable on Windows and foundation has:

- no clipped UI at 100%, 125%, 150%, 200%
- correct Persian samples
- correct English samples
- mixed Persian/English sample
- keyboard navigation
- light/dark PASS

---

# 16. Phase 3 — Document Lifecycle & Filesystem Safety

## Goal

یک فایل Markdown واقعی از create/open تا safe save کامل مدیریت شود.

## Scope

- New Markdown
- Open
- Save
- Save As if product behavior requires
- recent documents
- document metadata
- encoding strategy
- `.md`
- `.mmd`
- autosave
- dirty state
- atomic writes
- SHA-256 content revision
- external file watcher
- conflict state
- reload
- refuse unsafe overwrite
- rename/delete edge cases
- long path support
- Unicode filename support

## Critical Invariant

اگر فایل روی disk بعد از load توسط process دیگر تغییر کرد، برنامه نباید تغییر کاربر را silently overwrite کند.

## Required Tests

- UTF-8
- Persian filename
- Unicode content
- CRLF
- LF
- empty file
- large file
- external write
- external rename
- external delete
- save conflict
- atomic write failure simulation

## Exit Gate

Document lifecycle با evidence native Windows PASS باشد.

---

# 17. Phase 4 — Source Editor

## Goal

Source mode پایدار، سریع و قابل استفاده.

## Scope

- raw Markdown editing
- selection
- caret
- undo/redo
- keyboard shortcuts
- line/column
- syntax highlighting
- find hooks
- tab behavior
- code fences
- indentation
- clipboard
- RTL/LTR
- IME
- Persian typing
- large document behavior

## Editing Technology Gate

در ابتدای Phase یک spike کوتاه انجام شود.

اولویت:

1. Rust/WASM implementation اگر کیفیت production قابل دستیابی است.
2. در صورت failure معیارهای مشخص، یک editor engine browser-side محدود با adapter کوچک استفاده شود.

معیار انتخاب نه «پاک بودن stack» بلکه:

- source fidelity
- IME correctness
- selection correctness
- performance
- accessibility
- testability

است.

## Exit Gate

هیچ keypress یا formatting operation نباید silent source corruption ایجاد کند.

---

# 18. Phase 5 — Preview Rendering & Mermaid

## Goal

Preview نسخه Windows از نظر semantics با renderer فعلی Markowski برابر شود.

## Strategy

در قدم اول assets موجود renderer بررسی و در صورت سازگاری reuse شوند:

- `renderer.html`
- `renderer.css`
- `marked.min.js`
- `mermaid.min.js`

assets باید local bundle باشند.

## Scope

- Markdown render
- headings
- lists
- task lists
- blockquotes
- links
- images
- tables
- inline code
- fenced code
- syntax-highlight-compatible structure
- Mermaid fenced blocks
- standalone `.mmd`
- dark/light rendering
- Persian typography
- mixed RTL/LTR
- preview zoom
- render deduplication

## Security

- remote scripts forbidden
- HTML handling policy explicit
- external link handling explicit
- local file/resource scope restricted
- CSP defined

## Important Behavior

Preview نباید به خاطر unrelated UI state update دوباره render شود و selection/scroll را از بین ببرد.

## Exit Gate

Golden documents در `TestDocuments/` و Windows fixtures render correctly.

---

# 19. Phase 6 — Visual Editor & Formatting

## Goal

Editor mode واقعی Markowski با حفظ Markdown source.

## Scope

- headings
- bold
- italic
- strike if baseline supports
- lists
- numbered lists
- task lists
- blockquotes
- links
- images
- code
- code blocks
- tables
- paragraph operations
- formatting sidebar/toolbar
- selection-aware commands
- Persian text operations
- undo/redo integration

## Core Design Constraint

Visual Editor نباید کل Markdown را برای یک edit کوچک parse-and-reserialize کند مگر fidelity tests اثبات کنند هیچ اطلاعاتی از بین نمی‌رود.

ترجیح:

- source-range-aware operations
- block-aware editing
- minimal source patch
- stable document revision mapping

## Golden Round-Trip Tests

باید نمونه‌هایی با موارد زیر وجود داشته باشد:

- comments
- unusual spacing
- nested lists
- mixed RTL/LTR
- tables
- fenced code
- Mermaid
- inline HTML if supported
- links
- images

و مشخص شود edit unrelated، بخش‌های دیگر را تغییر نمی‌دهد.

## Exit Gate

Visual Editor برای featureهای parity دارای deterministic source output باشد.

---

# 20. Phase 7 — Search, Document Index, Navigation & Selection Bridge

## Goal

Smart Navigation مشابه macOS.

## Scope

- DocumentBlock
- stable runtime block handles
- headings
- source line ranges
- quoted text
- DocumentLocation
- location resolver
- literal search
- next/previous
- source highlight
- preview highlight
- TOC
- source ↔ preview navigation
- scroll target
- selection bridge
- selection actions placeholder

## Resolver Order

Windows implementation باید semantics این fallback را حفظ کند:

1. known local handle where valid
2. heading
3. quote
4. normalized/loose quote candidate
5. line range

AI نباید به internal renderer block ID وابسته شود.

## Mermaid Case

Navigation باید برای Mermaid reference حتی وقتی source token در SVG ناپدید می‌شود fallback مناسب داشته باشد.

## Exit Gate

search/navigation روی:

- plain Markdown
- headings
- repeated text
- Persian
- Mermaid
- long document

PASS باشد.

---

# 21. Phase 8 — Settings & Local Persistence

## Goal

زیرساخت تنظیمات production-grade.

## Scope

- app settings schema
- versioned migration
- window state
- theme
- zoom
- editor preferences
- model preferences placeholder
- recent file metadata
- chat storage foundation
- schema migration tests

## Rules

- secrets ممنوع
- settings corruption recovery
- atomic config update
- backwards-compatible migrations
- version field mandatory

## Exit Gate

upgrade/downgrade policy مستند و migration tests PASS.

---

# 22. Phase 9 — Windows Credential Manager & Security Foundation

## Goal

ذخیره امن AI secrets.

## Scope

- SecretStore trait
- Windows Credential Manager implementation
- create/read/update/delete
- provider account naming
- redaction
- memory exposure minimization
- error mapping
- settings UI integration
- connection state without exposing key
- secret-safe logs

## Forbidden

- plaintext JSON key storage
- registry plaintext
- Base64 fallback
- API key in panic/log
- API key returned unnecessarily to WebView frontend

در صورت امکان Tauri frontend فقط عملیات:

- has key?
- save new key
- delete key
- test provider

را trigger کند، نه اینکه persisted key را دوباره دریافت کند.

## Exit Gate

security tests و manual Windows Credential Manager validation PASS.

---

# 23. Phase 10 — AI Provider Core & Streaming

## Goal

Provider abstraction کامل و مستقل از UI.

## Required Providers

- Gemini
- OpenAI
- Anthropic
- OpenRouter
- Mistral
- Groq
- xAI
- DeepSeek
- Mock AI Provider

## Core Trait

Provider interface باید حداقل semantics این عملیات را داشته باشد:

- fetch models
- test connection
- stream response

## Scope

- HTTP clients
- provider endpoints
- request builders
- response parsers
- SSE/streaming
- cancellation
- timeout
- retry policy
- provider-specific error mapping
- mock transport
- fixture-driven tests

## Security

Authorization headers باید همیشه redacted باشند.

## Network Tests

Unit/integration tests نباید برای PASS شدن به API Key واقعی وابسته باشند.

Live-provider tests:

- opt-in
- separate
- never required for normal CI
- never print secrets

## Exit Gate

Mock + protocol fixtures تمام provider flows را validate کنند.

---

# 24. Phase 11 — Model Catalog, Preferences, Usage & Token Policies

## Goal

مدیریت مدل‌ها مطابق capabilityهای نسخه macOS.

## Scope

- live model catalog
- provider scoping
- text-model filtering
- configured-provider filtering
- searchable model picker data
- per-model allow-list
- initial model selection policy
- token counters
- exact vs estimated usage distinction
- per-model limits
- manual reset
- daily local-midnight reset
- remaining allowance
- output cap
- reasoning effort
- local persistence

## Important Invariant

Selected model تعیین‌کننده provider request است؛ آخرین provider toggle نباید routing را override کند.

## Exit Gate

routing/token policy tests exhaustive PASS.

---

# 25. Phase 12 — AI Sidebar, Chat & Request State Machine

## Goal

AI Assistant قابل استفاده در UI.

## Scope

- AI sidebar
- composer
- model picker
- streaming rendering
- stop/cancel
- retry where appropriate
- conversation
- local chat persistence
- error blocks
- status blocks
- Markdown AI responses
- empty states
- loading states
- request lifecycle

## Required State Machine

Conceptual equivalent:

```text
idle
  -> preparing
  -> thinking
  -> streaming
  -> validating
  -> proposed_edit
  -> applying
  -> idle

failure/cancel paths must be explicit
```

## Streaming Rule

متن stream شده‌ای که واقعاً به UI رسیده، صرفاً به دلیل cancel/error نباید بی‌دلیل ناپدید شود.

## Exit Gate

Mock Provider E2E tests state transitions را اثبات کنند.

---

# 26. Phase 13 — AI Context, References & Attachments

## Goal

AI واقعاً با سند باز کار کند، نه یک chat عمومی.

## Scope

- whole-document context
- selected-text context
- pinned selection
- source line references
- document location schema
- click-to-navigate
- preview selection actions:
  - Ask
  - Explain
  - Improve
- attachments
- supported type detection
- size limits
- provider capability checks
- attachment failure states

## Required Attachment Categories

طبق baseline فعلی:

- PDF
- Word documents
- spreadsheets
- images
- code/text files

پیاده‌سازی دقیق ارسال هر attachment می‌تواند provider-specific باشد.

## Privacy Rule

attachment یا document بدون Send صریح user به network فرستاده نشود.

## Exit Gate

reference navigation + attachment handling with mock/provider fixtures PASS.

---

# 27. Phase 14 — Agentic Document Operations, Diff Review, Undo & Revert

## Goal

امن‌ترین بخش AI editing.

## Response Types

Windows implementation باید semantic support برای این دسته‌ها داشته باشد:

- chat response
- document reference
- document operations
- legacy whole-document edit compatibility where required

## Document Operations

Operations باید scope مشخص داشته باشند، مثل:

- insert block
- replace block
- delete block
- targeted source edit

schema دقیق در ADR تعریف شود.

## Pre-Apply Safety

proposal باید حداقل:

- original document snapshot/reference
- original SHA-256
- summary
- proposed operations/output
- status

داشته باشد.

قبل از apply:

- current hash compare
- operation validation
- range/handle resolution
- conflict detection

## Diff

- deterministic line diff
- visible additions
- visible removals
- large diff handling
- review before apply

## Required Actions

- Apply
- Discard
- Undo
- Revert

## Critical Gate

اگر document بعد از proposal تغییر کرده، stale proposal نباید silently apply شود.

## Exit Gate

concurrency/stale-proposal/security regressions PASS.

---

# 28. Phase 15 — Windows Native Integration

## Goal

برنامه حس یک Windows application واقعی داشته باشد.

## Scope

- `.md` association
- `.mmd` association
- Open With
- command-line file open
- drag & drop
- single-instance behavior
- second-launch file routing
- recent files integration where feasible
- Explorer reveal
- external URL opener
- native dialogs
- app icon
- taskbar behavior
- window restore
- keyboard shortcuts
- Windows menu conventions

## Security

File association یا deep-link input باید untrusted input فرض شود.

## Exit Gate

real installed-build tests PASS.

---

# 29. Phase 16 — Reliability, Performance, Accessibility & International Text

## Goal

از «کار می‌کند» به «production quality» برسیم.

## Performance Targets

Benchmarks در Phase 0/16 با سخت‌افزار reference ثبت شوند.

سناریوها:

- cold start
- open 1 MB Markdown
- open 5 MB Markdown
- render large document
- long Mermaid
- search large document
- AI streaming UI
- diff large document

هدف اصلی:

- no UI freeze
- cancellation works
- no uncontrolled memory growth
- no render storm

## Accessibility

- keyboard-only navigation
- logical tab order
- visible focus
- screen-reader labels
- contrast
- reduced motion where relevant
- scalable text
- high DPI

## International Text

- Persian
- Arabic
- English
- mixed RTL/LTR
- emoji
- combining marks
- Unicode filenames
- IME

## Exit Gate

performance/accessibility/RTL test matrix completed.

---

# 30. Phase 17 — Packaging, Signing, Updates & Release Engineering

## Goal

تولید artifact قابل انتشار.

## Build Targets

- Windows x64
- Windows ARM64

## Packages

حداقل یکی برای GA:

- NSIS installer

ترجیحاً در صورت نیاز:

- MSI

## WebView2

Default strategy:

- Evergreen WebView2
- installer/runtime presence handling

Fixed runtime فقط با ADR و نیاز واقعی.

## Signing

قبل از GA:

- Authenticode signing path
- certificate handling procedure
- CI secret isolation
- signed installer validation

## Updater

- signed update manifest/artifacts
- rollback/failure behavior
- no unsigned update acceptance
- staged testing before production channel

## Release Artifacts

- installer
- version metadata
- checksums
- release notes
- SBOM
- license notices

## Exit Gate

clean machine install/update/uninstall validation PASS.

---

# 31. Phase 18 — Security & Privacy Hardening

## Goal

release security review مستقل از feature implementation.

## Threat Areas

- Tauri IPC
- capability permissions
- arbitrary file access
- path traversal
- symlink/junction edge cases
- WebView injection
- Markdown raw HTML
- Mermaid input
- external links
- attachment parsing
- provider responses
- prompt injection effects on local document operations
- credential exposure
- logs
- update chain
- installer
- dependency supply chain

## Mandatory Controls

- strict CSP
- least privilege Tauri capabilities
- no remote code loading
- explicit URL schemes
- sanitized/redacted logs
- dependency audit
- secret scan
- malicious Markdown fixtures
- malicious attachment fixtures where safe
- invalid AI operation fixtures

## Agentic Safety

AI output is untrusted data.

هر document operation باید توسط local deterministic validator تأیید شود.

## Exit Gate

تمام Critical/High findings:

- fixed
- or explicitly accepted by product owner with written risk acceptance

---

# 32. Phase 19 — Full Feature Parity & Regression Closure

## Goal

Windows را در برابر baseline واقعی macOS ارزیابی کنیم.

## Procedure

برای هر row در Feature Parity Matrix:

- macOS expected behavior
- Windows implementation
- automated evidence
- manual evidence where necessary
- PASS / PARTIAL / FAIL
- approved variance

## Cross-Platform Golden Fixtures

یک مجموعه shared documents برای:

- headings
- nested list
- tables
- code
- Mermaid
- Persian
- mixed RTL/LTR
- links/images
- very large content
- invalid Mermaid
- external change scenarios

## No Hidden Defer

قابلیت parity mandatory نمی‌تواند صرفاً برای رسیدن به Release Candidate به "later" منتقل شود مگر user صریحاً scope را تغییر دهد.

## Exit Gate

تمام parity items mandatory = PASS یا documented owner-approved variance.

---

# 33. Phase 20 — Windows Release Candidate & GA Gate

## Goal

تصمیم نهایی انتشار.

## RC Validation

- clean repository baseline
- exact commit
- all CI green
- Windows x64 native evidence
- ARM64 build/smoke evidence
- installer evidence
- update evidence
- security evidence
- no secret findings
- dependency audit
- accessibility review
- Persian/RTL review
- large-file review
- AI mock full-flow
- opt-in live provider smoke tests
- crash-free startup
- clean install
- upgrade install
- uninstall
- association open
- second-instance file open

## GA Blocking Issues

هرکدام از موارد زیر GA را block می‌کند:

- data loss
- silent overwrite
- secret leak
- unsigned/unsafe update path
- broken installer
- AI applying edits without user approval
- stale proposal overwrite
- renderer remote-code dependency
- critical accessibility navigation failure
- systematic RTL corruption

## Exit

فقط یکی:

- `GA_APPROVED`
- `GA_BLOCKED`

---

# 34. Testing Architecture

## 34.1 Unit Tests

برای pure Rust logic:

- document index
- location resolver
- Markdown formatting
- diff
- hash/revision
- AI response decoder
- provider parsing
- token accounting
- settings migrations
- security redaction

## 34.2 Integration Tests

- filesystem
- watcher
- safe save
- settings
- SQLite/store if used
- Credential Manager using isolated test targets where safe
- Tauri commands
- AI mock transport

## 34.3 Golden Tests

Golden fixtures برای:

- renderer inputs
- document operations
- formatting
- source round trip
- AI envelopes
- Mermaid
- RTL

## 34.4 E2E Tests

Windows native application:

- launch
- new file
- open
- edit
- save
- preview
- search
- AI mock
- diff review
- apply
- undo/revert
- settings
- restart persistence
- file association

Tauri/WebView UI automation باید از supported WebDriver approach استفاده کند.

## 34.5 Manual Evidence

فقط جاهایی که automation کافی نیست:

- typography
- DPI
- screen reader
- real installer
- credential UI
- code signing UI
- ARM64 smoke if runner unavailable

Manual evidence باید دقیقاً ثبت شود؛ جای test automation را بی‌دلیل نگیرد.

---

# 35. CI/CD Master Matrix

## Pull Request

- fmt
- check
- clippy
- unit
- integration where deterministic
- WASM build
- Windows app build
- security/dependency scan

## Main

تمام موارد بالا +

- packaged Windows build
- E2E suite
- artifact retention

## Release Candidate

تمام موارد بالا +

- installer
- signing
- updater validation
- SBOM
- checksums
- release evidence bundle

## macOS Regression

تا وقتی Swift/macOS در همان repository است:

- existing macOS build/test workflow نباید حذف شود.
- اگر shared resource تغییر کرد، macOS regression باید اجرا شود.
- Windows runner حق ندارد بدون evidence ادعا کند macOS PASS است.

---

# 36. Evidence Standard

هر Phase report باید حداقل این ساختار را داشته باشد:

```text
Phase Status
Git Baseline
Environment
Scope Implemented
Scope Not Implemented
Files Changed
Architecture Decisions
Tests Run
Exact Results
Security Checks
Acceptance Criteria
Known Limitations
Blockers
Git Final State
HANDOFF Updated
OKF Updated
Next Phase Readiness
```

هر test نتیجه باید:

- command
- exit status
- counts when available
- relevant artifact path

داشته باشد.

---

# 37. Acceptance Matrix Convention

شناسه‌ها:

```text
AC-WIN-P00-001
AC-WIN-P00-002
...
AC-WIN-P01-001
...
AC-WIN-P20-xxx
```

هر acceptance row:

```text
ID
Requirement
Type
Mandatory?
Automated/Manual
Evidence
Status
Notes
```

Status:

- OPEN
- PASS
- FAIL
- PARTIAL
- DEFERRED
- BLOCKED
- N/A

`DEFERRED` برای requirement mandatory به معنی Phase COMPLETE نیست، مگر Master Plan یا owner آن را صریحاً از scope خارج کند.

---

# 38. OKF Strategy

Repository فعلی از Google Open Knowledge Format v0.2 استفاده می‌کند.

نسخه Windows نیز باید همان canonical knowledge system را ادامه دهد.

Codex نباید یک documentation framework موازی بسازد.

در Phase 0:

1. official OKF v0.2 specification دوباره بررسی شود.
2. structure فعلی `OKF/` بررسی شود.
3. کم‌اختلال‌ترین روش معتبر برای اضافه کردن Windows concepts انتخاب شود.
4. root `OKF/index.md` همچنان entry point اصلی باقی بماند.
5. هر تغییر implementation که concept را stale می‌کند، همان Phase باید concept را update کند.
6. `OKF/log.md` در همان change update شود.

حداقل knowledge coverage Windows:

- architecture
- document lifecycle
- rendering
- visual editing
- navigation/search
- AI
- security
- persistence
- Windows integration
- release/update
- key components
- key views
- playbooks

---

# 39. Required Playbooks

تا قبل از RC بهتر است OKF playbooks برای این عملیات وجود داشته باشد:

- add AI provider
- change provider API
- add model capability
- add document operation
- change Markdown rendering
- add formatting command
- handle external file change
- add Windows integration
- rotate/update credential names
- add settings migration
- create release
- update WebView/runtime policy
- debug failed E2E
- recover from stale AI edit

---

# 40. Security Baseline

## Tauri

- capability ACLs are deny-by-default
- only required commands exposed
- no generic arbitrary command executor
- no arbitrary shell
- no unrestricted filesystem plugin access

## WebView

- strict CSP
- local assets preferred
- remote navigation blocked or delegated to system browser
- no remote script execution
- explicit bridge schema

## AI

- API response untrusted
- AI document operations validated locally
- no tool-style arbitrary filesystem operations in v1
- no auto-apply
- cancellation supported
- network errors preserve document safety

## Logs

Must redact:

- Authorization
- API keys
- cookies
- attachment raw sensitive content where not needed
- full provider request body when it contains document content

---

# 41. Data & Privacy Model

## Documents

Stored only where user selected.

## Preferences

Stored in app data.

## Chat History

Local storage only unless explicitly sent as context in a provider request.

## API Keys

Windows Credential Manager.

## AI Requests

Only explicit user-triggered requests.

## Telemetry

Default v1:

- no mandatory analytics
- no document telemetry
- no secret telemetry

هر telemetry آینده نیاز به separate product decision دارد.

---

# 42. Error Handling Standard

هیچ layer نباید error را به generic `"Something went wrong"` تقلیل دهد مگر UI secondary message باشد.

Internal typed errors باید categories قابل تشخیص داشته باشند:

- filesystem
- encoding
- conflict
- renderer
- Mermaid
- settings
- credential
- network
- provider auth
- provider quota
- provider model
- streaming
- malformed AI response
- invalid operation
- stale proposal
- attachment
- updater

User message باید actionable باشد ولی secret leak نکند.

---

# 43. Performance Architecture Rules

- file I/O خارج از blocking UI path
- hashing large content بدون freeze
- debounced watcher
- debounced expensive render where appropriate
- no preview render on unrelated state mutation
- cancel previous render/AI work when superseded where safe
- bounded conversation/context strategy
- avoid cloning huge documents repeatedly unless required for safety
- diff algorithm behavior برای large documents benchmark شود
- attachment reads size-capped

---

# 44. Dependency Policy

هر dependency جدید باید:

- purpose مشخص داشته باشد.
- active maintenance بررسی شود.
- license بررسی شود.
- امنیت بررسی شود.
- duplicate functionality ایجاد نکند.
- تا حد امکان minimal features فعال کند.

ممنوع:

- اضافه کردن crate فقط برای چند خط ساده بدون بررسی
- unmaintained crypto
- obscure secret storage
- downloading executable/runtime during normal app use without explicit design

`Cargo.lock` برای application باید commit شود.

---

# 45. Versioning

نسخه Windows باید مستقل از internal crate versioning ولی هماهنگ با product version باشد.

قبل از GA:

- SemVer
- product version source of truth
- installer version mapping
- updater version mapping
- migration version mapping

باید مشخص و مستند باشند.

---

# 46. Branching Recommendation

مدل پیشنهادی:

```text
main
  ├─ feature/windows-phase-00
  ├─ feature/windows-phase-01
  ├─ ...
```

هر Phase:

1. از latest validated `main`
2. branch کوتاه‌عمر
3. implementation
4. validation
5. PR/review
6. merge
7. next phase

یک branch بسیار طولانی `windows-development` ترجیح داده نمی‌شود، چون drift با macOS را زیاد می‌کند.

اگر workflow فعلی پروژه سیاست دیگری دارد، Phase 0 آن را مستند می‌کند.

---

# 47. Prohibited Shortcuts

Codex نباید:

- macOS Swift code را line-by-line به Rust ترجمه کند بدون طراحی
- business logic را داخل Leptos component دفن کند
- secret را به browser localStorage بدهد
- filesystem access unrestricted کند
- CDN برای Mermaid/marked اضافه کند
- fake test بنویسد که implementation واقعی را test نمی‌کند
- test skipped را PASS حساب کند
- live API را requirement معمول CI کند
- mock را به جای native Windows evidence جا بزند
- visual editor را با full-document rewrite ناامن پیاده کند
- conflict detection را حذف کند
- AI auto-apply کند
- unrelated macOS code را refactor کند
- README را قبل از implementation proof به feature completed تغییر دهد

---

# 48. Phase Dependency Graph

```text
P00 Baseline/Architecture
  ↓
P01 Foundation/CI
  ↓
P02 Shell/RTL/Theme
  ↓
P03 Document Lifecycle
  ↓
P04 Source Editor
  ↓
P05 Preview/Mermaid
  ↓
P06 Visual Editor
  ↓
P07 Navigation/Search
  ↓
P08 Persistence
  ↓
P09 Credentials/Security
  ↓
P10 AI Providers
  ↓
P11 Models/Usage
  ↓
P12 AI Sidebar/Chat
  ↓
P13 Context/References/Attachments
  ↓
P14 Agentic Edit/Diff
  ↓
P15 Windows Integration
  ↓
P16 Reliability/Performance/A11y
  ↓
P17 Packaging/Signing/Update
  ↓
P18 Security Hardening
  ↓
P19 Full Parity Closure
  ↓
P20 Release Candidate / GA
```

Parallel work فقط وقتی مجاز است که dependencies و source ownership روشن باشند.

---

# 49. Definition of Done — Windows v1

Markowski Windows v1 فقط زمانی Done است که:

## Product

- Preview complete
- Source complete
- Visual Editor complete
- Mermaid complete
- Search/navigation complete
- Persian/RTL complete
- AI providers complete
- AI model controls complete
- attachments complete
- references complete
- agentic edits complete
- diff/undo/revert complete

## Data Safety

- atomic writes
- external change detection
- stale-edit protection
- no known data-loss bug

## Security

- Credential Manager
- no plaintext keys
- secure IPC
- CSP
- dependency audit
- secret scan
- updater validation

## Windows

- native installer
- x64 validated
- ARM64 build/smoke
- file associations
- single-instance/file-open routing
- DPI
- keyboard
- accessibility baseline

## Engineering

- CI green
- unit/integration/E2E green
- OKF current
- HANDOFF current
- acceptance matrix complete
- release evidence complete

## Release

- signed distribution path
- update path
- release notes
- checksums
- SBOM
- clean install/upgrade/uninstall evidence

---

# 50. Post-v1 Opportunities — NOT Part of Windows v1

این موارد نباید باعث scope creep قبل از parity شوند:

- Linux release
- replacing macOS Swift implementation with Rust
- shared cross-platform Rust macOS app
- mobile app
- cloud sync
- collaboration
- accounts
- proprietary cloud backend
- plugin marketplace
- remote workspace
- autonomous filesystem agent

بعد از Windows GA می‌توان Rust core را برای Linux/macOS reuse کرد.

---

# 51. How Future Codex Phase Prompts Must Be Written

هر prompt اجرایی آینده برای GPT-5.6 Luna Max باید:

1. فقط یک Phase اصلی را authorize کند.
2. Master Plan را source of truth معرفی کند.
3. exact phase goals را تکرار کند.
4. scope boundaries را روشن کند.
5. forbidden work را مشخص کند.
6. ابتدا repository/OKF/HANDOFF audit را الزام کند.
7. implementation را بعد از baseline verification مجاز کند.
8. tests را command-level الزام کند.
9. native Windows evidence را در Phaseهای لازم بخواهد.
10. acceptance IDs را ببندد.
11. OKF update را mandatory کند.
12. HANDOFF update را mandatory کند.
13. mistakes log rule را mandatory کند.
14. git safety را روشن کند.
15. fake COMPLETE را ممنوع کند.
16. final report format را از همین Master Plan تبعیت دهد.

---

# 52. Phase Prompt Skeleton for Codex + GPT-5.6 Luna Max

این skeleton متن prompt نهایی هر Phase نیست، بلکه قرارداد ساخت prompt است.

```text
ROLE
You are the implementation owner for Markowski Windows Phase N.
Act as a senior Rust/Windows/Tauri engineer.

SOURCE OF TRUTH
1. Current user instruction
2. Phase N prompt
3. MARKOWSKI_WINDOWS_RUST_MASTER_PLAN_V1.0.md
4. AGENTS.md
5. accepted ADRs
6. OKF
7. source code

MANDATORY PREFLIGHT
- git status
- branch
- exact HEAD
- inspect HANDOFF
- inspect relevant OKF
- inspect current implementation/tests
- confirm Phase N-1 gate/evidence
- report contradictions before changing code

SCOPE
[phase-specific]

OUT OF SCOPE
[phase-specific]

IMPLEMENTATION RULES
- Rust-first
- thin Tauri IPC
- no secret exposure
- no unrelated macOS refactor
- no unsafe file overwrite
- no fake test
- no silent skipped validation

TESTS
[exact required commands + native validation]

DOCUMENTATION
- update OKF
- update OKF/log.md
- update acceptance matrix
- update HANDOFF.md
- update mistakes log on discovered agent mistake

GIT
No commit/push/rebase/reset/amend unless explicitly authorized.

EXIT
Only report COMPLETE if every mandatory acceptance has evidence.

FINAL REPORT
Phase Status
Git Baseline
Implementation
Files
Tests
Security
Acceptance Matrix
Evidence
Known Limitations
Git Final State
HANDOFF
Next Phase Readiness
```

---

# 53. Initial Risk Register

## R1 — Visual Editor Source Fidelity

**Risk:** rich visual editing Markdown can destroy source formatting.

**Mitigation:**

- Phase 4/6 spike
- source-range-aware operations
- golden round-trip tests
- prohibit broad reserialization until proven safe

**Severity:** Critical

---

## R2 — WebView Security

**Risk:** rendered Markdown or external content creates injection/navigation risk.

**Mitigation:**

- CSP
- local assets
- navigation restriction
- sanitize/explicit raw HTML policy
- no CDN

**Severity:** High

---

## R3 — AI Stale Edit/Data Loss

**Risk:** user edits document after AI proposal and old proposal overwrites new content.

**Mitigation:**

- SHA-256 proposal baseline
- pre-apply hash validation
- conflict UI
- no force apply without explicit new product decision

**Severity:** Critical

---

## R4 — Provider API Drift

**Risk:** provider APIs/models change.

**Mitigation:**

- adapters
- fixtures
- live opt-in smoke
- capability filtering
- no provider behavior hardcoded into UI

**Severity:** High

---

## R5 — Secret Exposure Across Tauri IPC

**Risk:** API key leaks to frontend/log.

**Mitigation:**

- native SecretStore
- key stays backend-side where possible
- explicit redaction tests
- scoped commands

**Severity:** Critical

---

## R6 — macOS Regression

**Risk:** shared assets/docs refactor breaks existing app.

**Mitigation:**

- minimal Swift changes
- shared-resource regression
- macOS CI where affected

**Severity:** High

---

## R7 — Large File Performance

**Risk:** repeated whole-document cloning/render/diff freezes UI.

**Mitigation:**

- benchmark
- debounce
- background operations
- block/index caching
- avoid unnecessary renders

**Severity:** Medium/High

---

## R8 — Windows DPI/IME/RTL Edge Cases

**Risk:** UI appears correct in English at 100% but breaks for Persian/high DPI.

**Mitigation:**

- test matrix from Phase 2 onward
- real Windows evidence
- IME + Persian fixtures

**Severity:** High

---

# 54. Recommended First Execution

اولین prompt بعد از پذیرش این Master Plan باید فقط **Phase 0** را اجرا کند.

Phase 0 نباید وارد ساخت featureهای Windows شود.

خروجی مطلوب آن:

1. baseline دقیق repository
2. feature parity inventory واقعی از source
3. Windows architecture package
4. ADR set
5. acceptance matrix
6. risk register refined
7. OKF extension
8. `HANDOFF.md`
9. Rust/Tauri build feasibility proof
10. Phase 1 authorization readiness

پس از `COMPLETE` شدن Phase 0، prompt Phase 1 صادر شود.

---

# 55. Technical Reference Snapshot

این Master Plan بر اساس baseline فعلی repository Markowski و مستندات رسمی stack نوشته شده است.

Primary references:

- Markowski repository:
  `https://github.com/sasanzare/markowski`

- Markowski README:
  `https://github.com/sasanzare/markowski/blob/main/README.md`

- Markowski agent instructions:
  `https://github.com/sasanzare/markowski/blob/main/AGENTS.md`

- Markowski OKF:
  `https://github.com/sasanzare/markowski/tree/main/OKF`

- Google Open Knowledge Format:
  `https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md`

- Tauri 2:
  `https://v2.tauri.app/`

- Tauri architecture:
  `https://v2.tauri.app/concept/architecture/`

- Tauri Windows prerequisites:
  `https://v2.tauri.app/start/prerequisites/`

- Tauri Windows installer:
  `https://v2.tauri.app/distribute/windows-installer/`

- Tauri WebDriver testing:
  `https://v2.tauri.app/develop/tests/webdriver/`

- Microsoft WebView2:
  `https://developer.microsoft.com/en-us/microsoft-edge/webview2/`

- Windows Credential Manager / credential APIs:
  `https://learn.microsoft.com/en-us/windows/win32/secauthn/credentials-management`

Dependencies must not be blindly pinned from this planning document. Phase 1 must resolve and lock mutually compatible stable versions and commit the application `Cargo.lock`.

---

# 56. Final Principle

هدف پروژه این نیست که بگوییم:

> "نسخه Rust بالا آمد."

هدف این است که بتوانیم با evidence بگوییم:

> **Markowski Windows یک desktop application production-grade، local-first و Rust-first است که قابلیت‌های اصلی Markowski macOS را بدون از دست دادن امنیت، کیفیت سند، تجربه فارسی/RTL، و کنترل کاربر بر AI ارائه می‌کند.**

تا قبل از اثبات این جمله، Windows v1 کامل محسوب نمی‌شود.
