# Phase 0 Evidence Log

This file records commands actually executed and the result category. It does
not turn unavailable runtime checks into passes.

## Git and repository

Commands executed:

```text
git status --short --branch
git log -1 --oneline
git rev-parse HEAD
git branch --show-current
git remote -v
rg --files -g 'AGENTS*.md' -g 'HANDOFF.md' -g 'README.md' -g 'RELEASE_NOTES.md'
```

Observed:

- branch `main`, tracking `origin/main`;
- HEAD `7d85b84c55f64636c69e746c37e98781182459c5`;
- HEAD subject `Stack download actions on iPhone layouts`;
- `origin` is `git@github.com:sasanzare/markowski.git`;
- at the start, only the pre-existing untracked `docs/windows/` master-plan
  directory was present; no staged changes;
- `HANDOFF.md` did not exist at the start and was created by this task.

## Source, tests, and fixtures

Commands executed:

```text
rg --files MarkView
rg --files MarkViewTests
rg --files TestDocuments
Get-ChildItem MarkView -Recurse -Filter *.swift | ...
Get-ChildItem MarkViewTests -Filter *.swift | ...
rg -n '^\s*func test' MarkViewTests
Get-FileHash -Algorithm SHA256 TestDocuments/*
```

Observed:

- six Swift test files and 262 declared `test...` methods;
- eight fixtures under `TestDocuments/`;
- renderer assets include `renderer.html` (1,595 lines), `renderer.css` (478
  lines), `marked.min.js` (39,972 bytes), and `mermaid.min.js` (3,339,881
  bytes);
- the complete fixture size/hash inventory is below.

| Fixture | Bytes | SHA-256 |
| --- | ---: | --- |
| `basic.md` | 186 | `5d6e7f8a3c1d48cd676b51f25778b1478af8fea64f1742f133fee6cc107dc2a4` |
| `descending-list.md` | 62 | `515b55b53781bf4a3b55fe9062e7643a90abd7134c2de9952406d23ff2300944` |
| `flowchart.mmd` | 284 | `fedaec2562564fe40bfb60f0293cc17c5ba33e359ebb6d1ce4ed996a0127b869` |
| `full-markdown.md` | 1,740 | `a6acfa2f11099672c681fe2451aa1870995860ff5a00dfb466e34af708dd7dbf` |
| `invalid.mmd` | 139 | `476860fd38c675d4789a2a99270716451b9ace9e7e015dc2d35664f823e69c71` |
| `markowski-commercial-demo.md` | 2,329 | `8735cf9f6648e8b98d6b11f645c8707f9738b7a2855155e10b42259a92b8a7bf` |
| `sequence.mmd` | 367 | `304e0910c0233f77b2fb104caa299db8da7b3de3a74f6296fb6c83dab2fb9c6f` |
| `showcase.md` | 1,783 | `3faadbb0ddfcdc68fabdfa29c5722e62d21adb14c59602d62ce07adeaefeb5c4` |

## Windows environment — initial Phase 0 audit

Commands executed included PowerShell OS information, registry CurrentVersion
reads, architecture checks, toolchain version checks, target/toolchain lists,
Visual Studio/SDK discovery, WebView2 registry discovery, and repository-wide
Tauri/Leptos/Cargo searches.

Observed results:

| Check | Result |
| --- | --- |
| PowerShell | 7.6.4, `Microsoft Windows 10.0.26200` |
| Kernel / `ver` | `10.0.26200.0` / `10.0.26200.8875` |
| Registry OS identity | Stale `ProductName=Windows 10 Home`, with `25H2`, build `26200`, UBR `8875`, edition `Core` |
| Architecture | 64-bit AMD64; `PROCESSOR_ARCHITECTURE=AMD64` |
| Active Rust | Initially observed as GNU; superseded by the remediation verification below |
| MSVC Rust toolchain | Initially installed but inactive; superseded by the remediation verification below |
| Rust targets | Initial audit did not include the WASM target |
| Node/npm | Node `v24.17.0`, npm `11.17.0` |
| Git/cmake | Git `2.46.0.windows.1`, CMake `4.3.3` |
| `cl.exe` / usable SDK | Initially not found from normal PowerShell PATH; superseded by developer-environment verification below |
| WebView2 | Registry client evidence for `Microsoft Edge WebView2 Runtime` version `151.0.4129.86` |
| WMI | `Win32_OperatingSystem` and `Win32_ComputerSystem` queries returned Access Denied |
| Production repo Windows implementation | No Cargo/Tauri/Leptos workspace found; only the ignored disposable smoke exists |

The initial audit did not infer Windows 11 from build number alone. The
remediation below reconciles it with Microsoft’s official release mapping.

## Phase 0 remediation checkpoint — paused 2026-08-16

Commands executed:

```text
rustc -Vv
cargo -V
rustup show
rustup toolchain list
rustup target list --installed
vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -format json
call "D:\\Program Files (x86)\\Microsoft Visual Studio\\18\\BuildTools\\VC\\Auxiliary\\Build\\vcvars64.bat" && where cl && where link && set WindowsSdkDir && set WindowsSDKVersion && cl
Get-ChildItem "C:\\Program Files (x86)\\Windows Kits\\10"
Get-ItemProperty HKLM:\\SOFTWARE\\WOW6432Node\\Microsoft\\EdgeUpdate\\Clients\\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
rustup target add wasm32-unknown-unknown
npm create tauri-app@latest -- tauri-leptos-smoke --template leptos --manager cargo --identifier com.markowski.phase0.smoke --tauri-version 2 --yes
cargo install trunk --locked
```

Observed:

| Check | Result |
| --- | --- |
| OS identity | Microsoft maps Windows 11 version 25H2 to OS build 26200; local `10.0.26200.8875` therefore reconciles as Windows 11 25H2 x64. The stale registry `ProductName` remains an observation. |
| Rust | `rustc 1.87.0`, host `x86_64-pc-windows-msvc`; MSVC is active/default |
| Visual Studio | Build Tools `18.9.0`, installation `D:\\Program Files (x86)\\Microsoft Visual Studio\\18\\BuildTools` |
| MSVC compiler | `cl.exe` resolved under MSVC `14.51.36231`; version `19.51.36256` for x64 |
| Linker | `link.exe` resolved under the same MSVC toolset |
| Windows SDK | `WindowsSdkDir=C:\\Program Files (x86)\\Windows Kits\\10\\`; `WindowsSDKVersion=10.0.26100.0\\` |
| WebView2 | `Microsoft Edge WebView2 Runtime`, `151.0.4129.86`, location `C:\\Program Files (x86)\\Microsoft\\EdgeWebView\\Application` |
| WASM target | `wasm32-unknown-unknown` installation succeeded |
| Tauri/Leptos scaffold | Official `create-tauri-app@4.6.2`, template `leptos`, Tauri `2`, created under the ignored `.artifacts/windows-phase0/tauri-leptos-smoke/` |
| Smoke source | Template greeting replaced with typed `phase0_smoke` request/response, restrictive CSP, narrow capability set, and visible smoke text |
| Trunk | `cargo install trunk --locked` downloaded `trunk v0.21.14` and began compilation, then was interrupted at the user’s request; exit code `1`, no installed `trunk` binary |
| Tauri CLI | Not installed; build was not started |

The official Microsoft mapping used for reconciliation is [Windows 11 release
information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information).

## Official references consulted

The following primary references were opened during Phase 0 and inform the
design (URLs are retained in the documents and final report):

- Tauri Windows prerequisites: `https://v2.tauri.app/start/prerequisites/`;
- Tauri WebDriver: `https://v2.tauri.app/develop/tests/webdriver/`;
- Tauri capabilities: `https://v2.tauri.app/security/capabilities/`;
- Tauri CSP: `https://v2.tauri.app/security/csp/`;
- Tauri Windows installer/WebView2 modes:
  `https://v2.tauri.app/distribute/windows-installer/`;
- Microsoft WebView2 security:
  `https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/security`;
- Microsoft WebView2 local content:
  `https://learn.microsoft.com/en-us/microsoft-edge/webview2/concepts/working-with-local-content`;
- Windows Credential Manager `CredWriteW`:
  `https://learn.microsoft.com/en-us/windows/win32/api/wincred/nf-wincred-credwritew`;
- GoogleCloudPlatform OKF v0.2 specification:
  `https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md`.
- Microsoft Windows 11 release information:
  `https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information`.

## Checks intentionally not run at the 2026-08-16 checkpoint

- `xcodebuild`, Swift compilation, and macOS UI tests: unavailable on this
  Windows host; marked `NOT RUN`, not pass.
- Tauri/Leptos smoke build: not yet run at that checkpoint. The user paused the
  task while `cargo install trunk --locked` was compiling; the later
  2026-08-17 build attempt is recorded below.
- Native Rust/MSVC smoke executable: not run in this checkpoint; only compiler,
  linker, SDK, and target verification completed.
- Tauri CLI installation, WASM build, native `.exe` link, app launch, WebView2
  rendering, and typed IPC runtime verification: not run.
- Native Windows launch/E2E: no binary exists; no evidence fabricated.
- Network/provider integration: no API credentials or live provider call used.

## Final validation commands to run after documentation is complete

```text
git diff --check
git status --short --branch
git diff --stat
rg -n 'windows/|tauri|leptos|Phase 1|production' docs/windows/phase-00 HANDOFF.md
```

Observed final validation:

- `git diff --check`: PASS (only normal LF/CRLF conversion warnings were
  reported for tracked Markdown/ignore files; no whitespace error);
- bounded trailing-whitespace scan over Phase 0 Markdown: PASS;
- required-file scan: PASS for all ten Phase 0 documents and twelve ADRs;
- ADR required-section scan: PASS;
- OKF Windows concept frontmatter scan: PASS;
- Markdown relative-link scan over the new handoff, OKF extension, and Phase 0
  documents: PASS;
- targeted token/private-key pattern scan over new documents: PASS; no
  credential-like value was added;
- `MarkView`, `MarkViewTests`, and `MarkView.xcodeproj` status scan: CLEAN;
- no production `windows/`, Cargo, Tauri, or Leptos workspace was found; the
  only implementation matches are the explicitly allowed ignored smoke under
  `.artifacts/windows-phase0/` plus documentation;
- final status remains on `main`, with no staged changes and no commit/push.

The native feasibility and launch gates remain `BLOCKED`/`NOT RUN` because the
smoke was paused before dependency completion and build/launch. Toolchain and
Windows identity blockers are resolved with the evidence above; they are not
counted as native build or runtime passes.

## Checkpoint validation after user pause

Commands executed after recording the pause:

```text
git diff --check
required-file/frontmatter/ADR-section/Markdown-link/trailing-whitespace scans
targeted token/private-key scan over docs and smoke
Test-Path windows, Cargo.toml, src-tauri
Get-Command trunk / cargo-tauri
Test-Path .artifacts/windows-phase0/tauri-leptos-smoke/target
```

Results:

- `git diff --check`: PASS; only normal LF/CRLF conversion warnings for tracked
  Markdown/ignore files;
- required files, OKF frontmatter, ADR sections, Markdown links, and new
  Markdown whitespace: PASS;
- targeted token/private-key scan: PASS;
- production `windows/`, root `Cargo.toml`, and root `src-tauri/`: absent;
- smoke `target/`, `trunk`, and `cargo-tauri`: absent;
- Git remains on `main` at `7d85b84c55f64636c69e746c37e98781182459c5`, with no
  staged changes.

## Phase 0 final-remediation attempt — 2026-08-17

The existing disposable smoke was reused. No production `windows/` workspace
was created and the existing `%USERPROFILE%\.cargo` directory was not moved or
deleted. A dedicated Cargo home and target area were prepared on D:
`D:\All projects\.cargo-markowski`.

### Toolchain and host verification

Commands executed:

```text
rustc -Vv
cargo -V
rustup show
rustup toolchain list
rustup target list --installed
cmd.exe /d /s /c 'call "D:\Program Files (x86)\Microsoft Visual Studio\18\BuildTools\VC\Auxiliary\Build\vcvars64.bat" && where cl && where link && set WindowsSdkDir && set WindowsSDKVersion && cl'
Get-ItemProperty HKLM:\SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}
```

Observed:

- `rustc 1.87.0`, host `x86_64-pc-windows-msvc`; Cargo `1.87.0`;
- active/default toolchain `stable-x86_64-pc-windows-msvc`;
- installed targets include `wasm32-unknown-unknown` and
  `x86_64-pc-windows-msvc`;
- `cl.exe` and `link.exe` resolve from Visual Studio Build Tools `18.9.0`;
- `WindowsSdkDir=C:\Program Files (x86)\Windows Kits\10\` and
  `WindowsSDKVersion=10.0.26100.0\`;
- MSVC compiler reports `19.51.36256` for x64;
- WebView2 reports `151.0.4129.86`.

### Tooling and build attempts

The existing Cargo registry cache was copied non-destructively to the D: Cargo
home (`robocopy` exit `1`, 34,874 files copied). The source cache contained
Trunk `0.21.14`, but no `tauri`, `tauri-build`, `tauri-cli`, or Leptos source.

Commands executed with `CARGO_HOME=D:\All projects\.cargo-markowski`,
`CARGO_TARGET_DIR=D:\All projects\.cargo-markowski\target` for tooling and
`D:\All projects\.cargo-markowski\target-smoke` for the smoke, and offline
mode where noted:

```text
robocopy 'C:\Users\moxfo\.cargo\registry' 'D:\All projects\.cargo-markowski\registry' /E /COPY:DAT /DCOPY:DAT /R:1 /W:1 /NFL /NDL /NP
$taskCargoHome='D:\All projects\.cargo-markowski'; $env:CARGO_HOME=$taskCargoHome; $env:CARGO_TARGET_DIR=Join-Path $taskCargoHome 'target'; $env:CARGO_NET_OFFLINE='true'; cargo install --path 'D:\All projects\.cargo-markowski\registry\src\index.crates.io-1949cf8c6b5b557f\trunk-0.21.14' --locked --offline --force
$taskCargoHome='D:\All projects\.cargo-markowski'; $env:CARGO_HOME=$taskCargoHome; & (Join-Path $taskCargoHome 'bin\trunk.exe') --version
$taskCargoHome='D:\All projects\.cargo-markowski'; $env:CARGO_HOME=$taskCargoHome; $env:CARGO_TARGET_DIR=Join-Path $taskCargoHome 'target-smoke'; $env:CARGO_NET_OFFLINE='true'; $env:NO_COLOR=$null; & (Join-Path $taskCargoHome 'bin\trunk.exe') build --release
$taskCargoHome='D:\All projects\.cargo-markowski'; $env:CARGO_HOME=$taskCargoHome; $env:CARGO_TARGET_DIR=Join-Path $taskCargoHome 'target-tools'; $env:CARGO_NET_OFFLINE='true'; cargo install tauri-cli --locked --offline
$env:CARGO_NET_OFFLINE='false'; cargo search trunk --limit 1; cargo search tauri-cli --limit 1
$env:HTTP_PROXY=$null; $env:HTTPS_PROXY=$null; $env:ALL_PROXY=$null; $env:NO_PROXY='*'; $env:CARGO_NET_OFFLINE='false'; Invoke-WebRequest -Uri 'https://index.crates.io/config.json' -UseBasicParsing -TimeoutSec 15
```

Results:

- Trunk install succeeded with exit `0`; installed artifact:
  `D:\All projects\.cargo-markowski\bin\trunk.exe`;
- `trunk --version` returned `trunk 0.21.14` with exit `0`;
- the first build invocation exited `2` because the host supplied
  `NO_COLOR=1`, which Trunk rejects as a boolean value; the recorded build
  result below is from a retry with that inherited setting removed;
- the real smoke `trunk build --release` reached Cargo metadata and failed with
  exit `1`: `no matching package named tauri found` in the offline crates.io
  index, required by `src-tauri`;
- `cargo install tauri-cli --locked --offline` failed with exit `101` because
  `tauri-cli` is not present in the offline registry;
- an online registry query and direct `https://index.crates.io/config.json`
  probe both failed because `index.crates.io` could not be resolved. No
  dependency or tool download could therefore be completed in this host.

No WASM output was produced: the smoke `dist/` directory is empty. No native
`.exe` was produced, so no Tauri build, launch, WebView2 rendering, typed IPC,
or clean-close evidence exists. The two native acceptance rows remain
`BLOCKED`; no runtime evidence is claimed.

### Security checks

Commands and results:

```text
rg -n -i --glob '!target/**' --glob '!dist/**' 'api[_-]?key|password|bearer|private[_ -]?key|secret|token|-----BEGIN' .artifacts/windows-phase0/tauri-leptos-smoke
```

Exit `1` with no matches: `SECRET_SCAN=PASS_NO_MATCHES`.

The exact external-script scan (`<script ... src=...>` or `<script ...
https://...>`) exited `1` with no matches. The only reviewed URLs are
documentation/schema URLs, localhost development configuration, SVG namespace
URLs, and the Tauri IPC CSP origin; none is a remote runtime script. The
capability scan passed with only `core:app`, `core:event`, `core:resources`,
and `core:window` permissions. The CSP scan passed for `default-src 'self'`,
the narrow WASM script directive, and the scoped IPC connect source; no shell,
filesystem, process, updater, or broad HTTP permission is declared.

The architecture and OKF concepts were not changed by this unsuccessful build
attempt, so no OKF content or `OKF/log.md` entry was necessary. `HANDOFF.md` and
this evidence log record the current blocker; Phase 1 remains out of scope.

## Phase 0 final remediation — completed 2026-08-17

This section supersedes the paused/blocked checkpoint above. The existing
disposable smoke project was reused; it was not recreated. No production
`windows/` workspace was created, and the user’s existing Rust installation
under `C:\Users\moxfo\.cargo` was not moved or deleted.

### Connectivity verification

Commands executed with the inherited proxy variables cleared and Cargo online
mode enabled:

```text
nslookup index.crates.io
Test-NetConnection index.crates.io -Port 443
cargo search tauri --limit 1
```

Observed:

- DNS resolution for `index.crates.io` succeeded;
- `TcpTestSucceeded : True` for TCP 443;
- Cargo registry access succeeded and returned `tauri = "2.11.5"`.

### Tauri tooling and compatibility preparation

The existing D: Cargo home remained in use:
`D:\All projects\.cargo-markowski`. Trunk `0.21.14` was already installed at
`D:\All projects\.cargo-markowski\bin\trunk.exe`. The required Tauri CLI was
installed there with `cargo install tauri-cli --locked`; the installed binary
is `D:\All projects\.cargo-markowski\bin\cargo-tauri.exe`, version `2.11.4`.

The verified host is Rust `1.87.0`, so the disposable smoke manifests pin the
known transitive MSRV-sensitive crates to compatible versions. The UI pins
`either_of 0.1.6`, `oco_ref 0.2.0`, and `idna_adapter 1.2.0`; the native crate
pins `plist 1.7.0`, `serde_with 3.12.0`, and `time 0.3.37`. These changes are
limited to the ignored smoke project.

### WASM / Leptos build

```text
trunk build --release
```

Exit `0`; the release build finished successfully. The generated `dist/`
contains `index.html`, the hashed CSS, the JavaScript/WASM pair, and the
Leptos frontend was embedded as the Tauri frontend source.

### Native Tauri build

```text
cargo-tauri build --no-bundle --ci
```

Exit `0`. The real native release executable was produced at:

```text
D:\All projects\.cargo-markowski\target-smoke\release\tauri-leptos-smoke.exe
```

Observed artifact metadata:

- size: `9,090,048` bytes;
- SHA-256: `CED9DA547617BAA7B7685686BD0933F9FBB8E6718A776DE59DC4A5EDA72268D1`;
- Rust host: `x86_64-pc-windows-msvc`;
- Trunk: `0.21.14`;
- Tauri CLI: `2.11.4`.

An earlier bundled `cargo-tauri build --ci` attempt linked the executable but
failed in the optional NSIS helper download. The acceptance build uses
`--no-bundle`, which directly proves the required native `.exe` and avoids
treating optional installer packaging as the Phase 0 executable gate.

### Native launch, WebView2, and typed IPC

The produced executable was launched from the exact path above. The returned
native window title was `Markowski Windows Phase 0 Smoke`. WebView2 accessibility
text was:

```text
Markowski Windows Phase 0 Smoke
Leptos/WASM frontend → typed Tauri command → Rust response
native-rust-bridge-ok
```

The frontend serialized the typed `{ request: { operation: "phase0-smoke" } }`
payload, invoked the registered `phase0_smoke` Rust command, decoded the typed
response, and rendered the expected `native-rust-bridge-ok` value. The window
was then closed through its native close control; a subsequent application
enumeration returned no smoke process/window.

### Security checks

The following checks were run against the smoke source/configuration, excluding
generated `target/` and `dist/` output where appropriate:

- targeted credential/private-key/token scan: exit `1`, no matches;
- external runtime script scan: exit `1`, no remote script tags;
- capability permissions: only `core:app:default`, `core:event:default`,
  `core:resources:default`, `core:window:default`, and the generated,
  command-specific `allow-phase0-smoke` permission;
- no shell, filesystem, process, updater, or broad HTTP permission is declared;
- CSP has `default-src 'self'`, no wildcard, no remote `script-src`, and only
  the scoped Tauri IPC connect source (`ipc:` / `http://ipc.localhost`);
- the production repository root has no `windows/`, `Cargo.toml`, or
  `src-tauri/` workspace.

### Final Phase 0 gate result

The real WASM build, native `.exe` build, WebView2 launch, typed IPC response,
and clean close are now evidenced. Therefore:

- `AC-WIN-P00-020 = PASS`;
- `AC-WIN-P00-021 = PASS`;
- final mandatory matrix: `PASS: 28`, `BLOCKED: 0`, `FAIL: 0`, `PARTIAL: 0`,
  `OPEN: 0`;
- Phase 1 was not started.
