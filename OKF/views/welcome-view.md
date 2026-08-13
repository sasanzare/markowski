---
type: View
title: WelcomeView
description: Markowski's launch window for creating, opening, and returning to recent Markdown files.
resource: MarkView/Views/Welcome/WelcomeView.swift
tags: [view, onboarding, recent-files, document]
status: stable
generated: { by: codex/gpt-5, at: 2026-08-13T16:35:00Z }
---

# What it does

`WelcomeView` is a standalone launch window, not part of a document
canvas. It introduces Markowski, creates a Markdown file through a save
panel rooted in the user's Downloads folder, opens existing supported
files, and lists up to ten recent Markdown documents.

The supplied waving Markowski character is centered at the top of the
brand panel as dedicated welcome artwork; the smaller assistant image
remains available to the in-document assistant surfaces.

Recent files come from `NSDocumentController`, are filtered to existing
`.md`, `.markdown`, and `.mmd` URLs, deduplicated, and opened in normal
`DocumentGroup` windows. The welcome window closes after a successful
create/open action.

# Save behavior

Creating a file establishes its final URL before the editor opens. This
lets SwiftUI's `DocumentGroup` autosave subsequent `FileDocument` edits
in place and avoids presenting an unexplained untitled document.
