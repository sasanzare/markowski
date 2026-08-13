---
type: View
title: DocumentStarterView
description: What an empty Markdown document shows instead of a blank page — templates plus an explanation of how editing works.
resource: MarkView/Views/Editing/DocumentStarterView.swift
tags: [view, editing, onboarding]
status: deprecated
generated: { by: claude-code/opus-5, at: 2026-08-12T00:00:00Z }
---

# Retired runtime path

This view is retained temporarily for its template definitions and
existing test coverage, but `DocumentView` no longer presents it. Empty
document onboarding moved to the independent [WelcomeView](welcome-view.md),
and new documents are assigned a Downloads-backed URL before their editor
opens.

# Original purpose

`ContentView` used to route an empty, unsaved document to a separate
drop-target screen instead of the editor. That screen had no toolbar and
no panels, and its "New Markdown" button called `newDocument`, which
produced another untitled document showing the same screen — pressing it
appeared to do nothing at all. `ContentView` now always presents
`DocumentView`; a new document is a document, it just has no text yet.

The empty case is handled inside the editor instead, by this view. That
matters because editing happens by double-clicking a block, and an empty
document has no blocks — so a blank preview was a dead end too.

`DocumentStarter.shouldOffer(text:fileExtension:)` is the rule, kept
separate from the view so the routing that broke is covered by a test.

This replaces the blank preview whenever the Markdown document is empty
(Mermaid files keep their own behaviour). It offers six templates — blank
note, meeting notes, checklist, table, project README, and a right-to-left
Persian document — each of which produces real blocks the moment it is
chosen. Alongside them it states the four things that are otherwise
undiscoverable: double-click to edit, hover between blocks for `+`, ⌘⌥F
for the formatting panel, and Source for raw Markdown.

Choosing a template goes through `applyEditWithUndo`, so it lands in the
same undo history as every other edit.

Opening an existing file and dropping one onto the window came from the
screen this replaces, so both live here now rather than being lost with
it.
