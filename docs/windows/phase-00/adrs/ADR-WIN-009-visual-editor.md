# ADR-WIN-009: Semantic visual editor with explicit fidelity

- Status: Proposed
- Date: 2026-08-16
- Scope: Leptos/WASM editor

## Context

The macOS TextKit 2 editor separates semantic attributes from visible Markdown
syntax, uses live table attachments, and serializes a rich model. It provides
excellent editing behavior but not universal byte preservation.

## Decision

Build the Windows visual editor as a semantic Leptos surface backed by the shared
Rust Markdown model. Keep Source mode as a plain text editor. Reuse the product
interaction contract only where the Phase 4/6 spike proves selection, tables,
IME, bidi, undo, and source synchronization. Preserve unknown constructs in a
raw/source lane.

## Alternatives and why rejected

- `contenteditable` with ad-hoc Markdown parsing: rejected for selection,
  tables, IME, and transaction complexity.
- Rendered HTML as the editor: rejected because semantics/source ranges are lost.
- Immediate full re-render on every keystroke: rejected for caret/IME stability.

## Consequences

The editor needs a selection model, transaction log, decorations, and explicit
source synchronization. Some constructs remain Source-only initially.

## Security

Editor HTML is not trusted content; DOM decorations cannot invoke native APIs;
clipboard/paste is sanitized at the model boundary.

## Testing

Phase spike acceptance must cover round trip, caret stability, selection mapping,
tables, keyboard shortcuts, IME, RTL, undo, and large documents.

## Cross-platform

Semantic model fixtures are shared with macOS; the actual text engine and input
behavior are platform-specific and need separate E2E evidence.

## Open questions

Choose the final editor DOM strategy, whether a hidden textarea/input bridge is
needed for IME, and which raw blocks are editable in the first release.
