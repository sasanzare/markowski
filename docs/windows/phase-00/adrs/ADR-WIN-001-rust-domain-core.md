# ADR-WIN-001: Rust domain core

- Status: Proposed
- Date: 2026-08-16
- Scope: Windows architecture / domain boundary

## Context

The Windows plan names Rust as the runtime language, while the existing product
is Swift/AppKit/SwiftUI. A direct Swift-to-Rust translation would copy UI and
platform assumptions into a new backend and make parity difficult to test.

## Decision

Implement a platform-neutral Rust domain core around immutable document
snapshots, typed revisions, Markdown operations, navigation locations, AI
proposals, and persistence traits. Keep Tauri, Leptos, WebView2, HTTP,
filesystem, and Windows APIs outside the core crates.

## Alternatives and why rejected

- Port Swift models line by line: rejected because it preserves the wrong
  boundaries and makes the Windows UI the implicit authority.
- Put all behavior in Tauri commands: rejected because commands become
  untestable business logic and widen the IPC attack surface.
- Use a JavaScript-only backend: rejected because file safety, concurrency,
  secret storage, and Windows integration need a typed native boundary.

## Consequences

The core is portable and unit-testable, but adapters and DTO mapping add work.
The domain API must be designed before UI convenience APIs.

## Security

No core API accepts arbitrary paths, scripts, provider payloads, or secrets. All
external data enters through validated types and explicit traits.

## Testing

Pure Rust tests cover operations, hashes, conflicts, parser/serializer behavior,
and AI state transitions without Windows or WebView2.

## Cross-platform

The core can be reused by a future macOS or other desktop shell, but the Phase 0
task does not change the existing macOS target.

## Open questions

Choose crate names and async/runtime boundaries after the first disposable build;
define whether document revisions are monotonic integers, UUIDs, or both.
