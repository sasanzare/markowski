---
type: Swift Type
title: DiffEngine
description: LCS-based line diff between the current document and an AI-proposed rewrite, used to render the diff review UI.
resource: MarkView/Services/Diff/DiffEngine.swift
tags: [component, diff, ai]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`computeDiff(original:modified:)` splits both strings on `\n`, builds a
Longest Common Subsequence matrix over the two line arrays, then
backtracks it into a `DiffSummary` (`additions`, `deletions`, and an
ordered `[DiffLine]` of `.same`/`.added`/`.removed` lines). This is a
line-level diff, not a word/character diff, matching how
[DiffReviewSheet](/views/diff-review-sheet.md) and
[AIDiffView](/views/diff-review-sheet.md) present changes.

`firstChangedLine(original:modified:)` reuses `computeDiff` to find the
1-based line number of the first difference, so the review UI can
auto-scroll to it instead of opening at the top of a possibly-long diff.

# Complexity note

The LCS matrix is `O(m × n)` in lines and space, built with a full
`[[Int]]` grid (no space-optimization), so `computeDiff` bounds what
reaches it:

1. The identical leading and trailing lines are peeled off first and
   emitted as `.same`. Since a proposal almost always rewrites a small
   region of a large document, this is what keeps the cost proportional
   to the change rather than to the file — the sidebar rebuilds this diff
   on every SwiftUI body evaluation, so an untrimmed 2,000-line document
   meant a 4,000,000-cell matrix per render.
2. If the differing region still exceeds `maximumMatrixCells`
   (1,000,000), it is reported as a wholesale replacement — every old
   line `.removed`, every new line `.added` — instead of blocking the
   main thread on an alignment nobody would read line by line.

Trimming does not change the result for any input small enough to align:
the reconstructed original and modified sides are still exact.
