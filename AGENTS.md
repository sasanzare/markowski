# Agent instructions for this repository

This repository ships a knowledge bundle at [`OKF/`](OKF/index.md), written in
[Open Knowledge Format (OKF) v0.2](https://github.com/GoogleCloudPlatform/knowledge-catalog/blob/main/okf/SPEC.md).
It documents MarkView's architecture, components, and views. Read it
before exploring the source tree cold — it exists so you don't have to
re-derive the app's structure from scratch every session.

## How to use it

1. **Start at [`OKF/index.md`](OKF/index.md)**. It's a plain markdown
   directory listing (no tooling required) linking to `overview.md` and
   the four sections: `architecture/`, `components/`, `views/`,
   `playbooks/`.
2. **Read `OKF/overview.md` first** for the app's purpose, stack, and
   top-level source layout.
3. **Prefer `architecture/*.md` over reading source directly** when you
   need to understand how a subsystem works end-to-end (document
   lifecycle, rendering pipeline, navigation/search, the AI assistant).
   Each one links out to the individual `components/*.md` and
   `views/*.md` concepts it's built from.
4. **Each concept's `resource` frontmatter field is the actual source
   file it describes** — follow it when you need the real
   implementation, not just the summary. The docs describe *why* and
   *how things fit together*; the code is still the source of truth for
   exact behavior.
5. **Check `OKF/playbooks/`** before implementing a change that matches
   a documented pattern (for example, adding a new AI provider) — it may
   already spell out the exact steps and the files that do **not** need
   to change.

## Concept format, briefly

Every file under `OKF/` other than `index.md` and `log.md` is a concept:
YAML frontmatter (`type`, `title`, `description`, `resource`, `tags`,
`status`, `generated`) followed by a markdown body. Links use
bundle-relative paths starting with `/` when crossing between
`OKF/architecture/`, `OKF/components/`, `OKF/views/`, and
`OKF/playbooks/`.

## Keeping it current

If you make a change that would make one of these concepts wrong or
incomplete — a renamed type, a new provider, a changed flow — update the
corresponding `OKF/**/*.md` file in the same change, and add an entry to
[`OKF/log.md`](OKF/log.md). Stale docs are worse than no docs: prefer
updating over leaving a note.
