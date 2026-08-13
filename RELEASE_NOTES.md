# Markowski 1.0 Beta

First public build. Free, native macOS, no account.

## What's in it

**A document editor, not a syntax editor.** Type `- `, `# `, `> `, `1. ` and the
markers disappear into real structure. ⌘B / ⌘I / ⌘K work as expected. Saves as
ordinary Markdown that any other tool can read.

**Tables that behave like tables.** Drag column borders to resize. Merge cells
across rows and columns. Align per cell, horizontally and vertically. Arrow keys
move between rows; Tab past the last cell grows the table. A plain table stays
plain Markdown — only one using merges or per-cell alignment becomes HTML, so
nothing is silently lost on save.

**A selection toolbar.** Select text, get block style, bold, italic, code,
highlight, link, and "Ask" without leaving the text.

**Diagram export.** Mermaid diagrams render inline and export as Copy / PNG /
SVG at 2×, matching what's on screen exactly.

**Persian and RTL tooling.** Scans the document, reports what is actually wrong
(Arabic letters, missing نیم‌فاصله, punctuation) with counts and worked
examples, and leaves code blocks and English punctuation alone.

**An assistant with context.** Attach PDFs, Word, Excel, and source files —
text is extracted locally and shown to you before it is sent. Chats are saved
and fully deletable, with a storage panel that reclaims attachment space.

## Known limitations

- Not notarised by Apple. First launch: right-click → Open.
- The assistant needs your own API key (Gemini, OpenAI, or Anthropic).
- No collaborative editing or plugin API yet.

## Install

1. Open the DMG, drag Markowski to Applications.
2. Right-click Markowski → Open → Open (first launch only).

Requires macOS 14 or later.
