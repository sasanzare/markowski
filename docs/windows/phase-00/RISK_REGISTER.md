# Windows Phase 0 Risk Register

Status is the Phase 0 state, not a claim that a risk is solved.

| ID | Risk | Evidence / trigger | Impact | Mitigation / owner | Status |
| --- | --- | --- | --- | --- | --- |
| R-WIN-001 | Editor cannot round-trip source faithfully | macOS semantic parser/serializer normalizes output; raw blocks are partial | Data loss or distrust | Two fidelity tiers, raw-block preservation, corpus goldens, Phase 4/6 spike | OPEN |
| R-WIN-002 | WebView2 behavior differs by runtime/build | WebView2 is system-serviced and current host has no native app | Render/IPC regressions | Pin minimum runtime, test Evergreen/fixed policy, native E2E matrix | OPEN |
| R-WIN-003 | Stale AI proposal overwrites unsaved edits | Sidebar checks disk hash; in-memory race remains | Data loss | Memory revision + source hash + disk identity recheck; fail closed | OPEN / HIGH |
| R-WIN-004 | Provider API/schema drift | Eight providers use distinct discovery/stream/image behavior | Broken AI or wrong model route | Typed adapter contract, mocks, capability catalog, response limits | OPEN |
| R-WIN-005 | Secret leaks across IPC/logs/storage | macOS has Base64 `UserDefaults` fallback | Credential compromise | Credential Manager only, redaction tests, negative secret scans | OPEN / HIGH |
| R-WIN-006 | Windows changes regress macOS | Shared docs/assets/contracts and one repo | Product regression | macOS CI lane and no Swift changes in Phase 0 | OPEN |
| R-WIN-007 | Large document blocks UI or diff | macOS diff has bounded matrix but renderer is DOM-heavy | Freeze/poor UX | Measure thresholds, worker/off-main rendering, chunked/wholesale fallback | OPEN |
| R-WIN-008 | DPI/IME/RTL behavior differs | macOS behavior does not prove Windows text stack | Input or accessibility defects | Native Windows IME/bidi tests, per-monitor DPI E2E, font fallback matrix | OPEN |
| R-WIN-009 | Local resource path escapes document scope | macOS `mvlocal` accepts standardized absolute image paths | Local file disclosure | Canonical-root allowlist, reparse/symlink rejection, hostile corpus | OPEN / HIGH |
| R-WIN-010 | Host support identity is misclassified | Registry says Windows 10 Home while build/display is 26200/25H2 | Invalid release claim | Microsoft release mapping now reconciles the host as Windows 11 25H2 x64; retain the stale registry observation | RESOLVED FOR THIS HOST |
| R-WIN-011 | Native feasibility cannot be demonstrated on current host | MSVC/SDK now verified; disposable smoke scaffold exists but is not built | Phase schedule uncertainty | Finish Trunk/Tauri installation, build, launch, and record evidence before Phase 1 | OPEN |
| R-WIN-012 | Renderer security configuration is copied from macOS unchanged | No observed CSP; Mermaid `loose`; raw HTML path | XSS/local access | Security-first renderer spike and explicit CSP/HTML/Mermaid policy | OPEN / HIGH |
| R-WIN-013 | Persistence schema traps future migrations | Chat/settings layout not yet selected for Rust | Upgrade/data loss | Versioned schemas, migration tests, backup/rollback plan | OPEN |
| R-WIN-014 | Installer/runtime update fails offline or under enterprise policy | WebView2/DLP/ACL conditions vary | App will not launch or be quarantined | Evergreen/fixed decision, signed artifacts, clean-machine tests | OPEN |

Highest priority before Phase 1: R-WIN-001, R-WIN-003, R-WIN-005, R-WIN-009,
R-WIN-011, and R-WIN-012.
