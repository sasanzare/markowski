# ADR-WIN-004: Markdown source authority and fidelity tiers

- Status: Accepted as product invariant; implementation Proposed
- Date: 2026-08-16
- Scope: Document model and editor

## Context

MarkView persists Markdown/Mermaid text. Its semantic Editor parses to a rich
model and serializes back, while Preview block edits splice source ranges. These
paths do not provide the same byte-level guarantee.

## Decision

Plain Markdown source remains the durable authority. Windows exposes two explicit
fidelity tiers: a source tier that preserves bytes outside intentional edits and
a semantic tier that may normalize supported Markdown. Raw/unsupported blocks
are retained or visibly marked; silent discard is forbidden.

## Alternatives and why rejected

- Rich model as the only authority: rejected because source formatting and
  unknown constructs would be lost.
- Rendered DOM as authority: rejected because it cannot reproduce source.
- Claim universal byte-perfect WYSIWYG: rejected as not supported by the current
  macOS architecture or ordinary Markdown parsing.

## Consequences

The editor must disclose normalization behavior and maintain parser/serializer
goldens. Some advanced Markdown remains source-only.

## Security

Source content is data; raw HTML and Mermaid are sanitized/isolated by renderer
policy and never become native commands.

## Testing

Fixed-point, source-range, raw-block, CRLF/BOM, table-span, and large-corpus
goldens are mandatory.

## Cross-platform

The contract applies to Windows and future shared behavior; it does not alter
macOS code in Phase 0.

## Open questions

Define the user-facing normalization indicator and the exact set of constructs
that the semantic editor supports in the first Windows release.
