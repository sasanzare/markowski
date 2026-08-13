---
type: View
title: FindBarView
description: In-document search bar — query field, match count, and next/previous navigation.
resource: MarkView/Views/Search/FindBarView.swift
tags: [view, search]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

A thin UI over [DocumentNavigator](../components/document-navigator.md)'s
search state: binds to `searchQuery`, displays `searchMatches.count` and
`selectedMatchIndex`, and calls `performSearch`, `nextMatch`, and
`previousMatch`. Visibility is toggled via
`DocumentNavigator.isSearchPresented` (wired to the app's Find command —
see [AppCommands](../MarkView/Commands/AppCommands.swift)).

All matching logic — building the regex, resolving line numbers,
highlighting in both the source view and the preview — lives in
`DocumentNavigator`, not here; this view is presentation only.
