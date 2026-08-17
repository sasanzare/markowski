# Windows Support Matrix

Status: PRODUCT TARGET RECORDED; NATIVE VALIDATION PENDING.

This is the intended support policy from the master plan, separated from what
the current machine proves.

| Target | Build/validation requirement | Phase 0 status | Release position |
| --- | --- | --- | --- |
| Windows 11 x64, standard user | MSVC Rust host, C++ Build Tools, Windows SDK, WebView2, packaged launch, core E2E | BLOCKED on this host; no native binary | Mandatory v1 baseline |
| Windows 11 ARM64 | ARM64 Rust target/build plus real smoke/E2E and installer validation | BLOCKED; no ARM64 target installed | Required before GA ARM64 claim |
| Windows 10 | Build/runtime behavior may be investigated, but not mandatory for v1 | Not validated | Not a v1 commitment |
| Windows 32-bit | No planned target | N/A | Out of scope |
| Server/unsupported editions | No product commitment | N/A | Out of scope unless separately approved |

## Current host evidence

The current host reports:

- PowerShell 7.6.4;
- kernel `10.0.26200.0`, `cmd /c ver` `10.0.26200.8875`;
- registry `ProductName=Windows 10 Home` is stale/contradictory metadata;
  `DisplayVersion=25H2`, `CurrentBuild=26200`, and `UBR=8875` are consistent
  with Windows 11 25H2 x64 according to Microsoft’s release mapping;
- 64-bit AMD64 process/OS;
- active/default Rust `1.87.0` with host `x86_64-pc-windows-msvc`;
- Visual Studio Build Tools `18.9.0`, MSVC compiler `19.51.36256`, and linker
  resolved through `vcvars64.bat`;
- Windows SDK `10.0.26100.0` under `C:\\Program Files (x86)\\Windows Kits\\10\\`;
- WebView2 Runtime registry evidence at version `151.0.4129.86`;
- WMI `Win32_OperatingSystem`/`Win32_ComputerSystem` queries denied by the
  environment.

Microsoft’s [Windows 11 release information](https://learn.microsoft.com/en-us/windows/release-health/windows11-release-information)
maps version 25H2 to OS build 26200 and lists build 26200.8875. The host is
therefore recorded for this remediation as `Windows 11 25H2 x64`; the stale
registry ProductName remains an observation, not a release blocker.

Native support is still not claimed: no Tauri binary has been built or launched
yet.

## Installer/WebView2 policy to decide in Phase 1

The release should choose one and test it explicitly:

- Evergreen WebView2 with installer/runtime presence checks, relying on Windows
  servicing for security updates; or
- fixed runtime for controlled/offline environments, accepting the much larger
  installer and a separate patch process.

The choice must include minimum runtime version, offline behavior, enterprise
proxy/DLP/ACL guidance, and a safe failure screen. The application must never
silently launch with a missing/incompatible runtime.

## Support entry/exit gates

To move a target from `PLANNED` to `SUPPORTED`, attach a reproducible build log,
binary hash, installer verification, WebView2 version, native E2E result, and
known-issues list. A platform that only compiles or only launches is not fully
supported.
