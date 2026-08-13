---
type: View
title: DiffReviewSheet
description: Modal review of an AI edit proposal — the line diff, and accept/discard actions.
resource: MarkView/Views/AI/DiffReviewSheet.swift
tags: [view, ai, diff]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

Presents an `AIEditProposal` (`summary`, `updatedDocument`,
`originalHash`, `status`) as a diff between the current document and
`updatedDocument`, computed by
[DiffEngine.computeDiff](../components/diff-engine.md) and rendered line
by line (`AIDiffView.swift` holds the actual added/removed/same line
rendering; `DiffReviewSheet.swift` is the sheet chrome — summary text,
scroll-to-first-change via `DiffEngine.firstChangedLine`, and the
accept/discard buttons).

# Accept path

Accepting re-checks `originalHash` against the current document's hash
(via [DocumentSafetyService.computeHash](../components/document-safety-service.md))
before applying — if the document changed since the proposal was
generated, the apply is refused rather than silently overwriting
newer edits, and the proposal's `status` becomes `.discarded` instead of
`.applied`. See the "Edit proposals and diff review" section of
[ai-assistant](../architecture/ai-assistant.md) for the full flow this
sheet sits at the end of.
