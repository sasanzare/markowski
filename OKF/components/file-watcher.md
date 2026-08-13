---
type: Swift Type
title: FileWatcher
description: Detects when the open file changes on disk from outside the app, using a debounced DispatchSourceFileSystemObject.
resource: MarkView/Services/FileWatcher.swift
tags: [component, filesystem, dispatchsource]
status: stable
generated: { by: claude-code/sonnet-5, at: 2026-08-12T00:00:00Z }
---

# What it does

`FileWatcher` is an `ObservableObject` publishing `fileDidChange: Bool`.
`startWatching(url:)` opens the file with `open(path, O_EVTONLY)` and
attaches a `DispatchSourceFileSystemObject` watching
`[.write, .extend, .attrib, .link, .rename, .revoke]` on a background
utility queue.

# Debouncing

Each event cancels any pending debounce `DispatchWorkItem` and schedules
a new one 0.25s out, so a burst of filesystem events (common with editors
that write via a temp file + rename, or with `git checkout`) collapses
into a single `fileDidChange = true` on the main queue instead of
flooding the UI.

# Security-scoped access

`startWatching` brackets the `open()` call with
`startAccessingSecurityScopedResource()`/`stopAccessingSecurityScopedResource()`,
matching the pattern used by [DocumentLoader](document-loader.md), since
the watched URL may come from the sandbox.

# Lifecycle

`stopWatching()` cancels the dispatch source (which closes the file
descriptor in its cancel handler) and clears the debounce work item;
`deinit` calls it, so a watcher does not leak an open file descriptor
past the owning object's lifetime.
